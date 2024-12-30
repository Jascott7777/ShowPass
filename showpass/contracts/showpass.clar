;; ShowPass - Decentralized Event Ticketing System with Refund Insurance
;; Description: Smart contract for minting and managing NFT event passes with transfer restrictions and refund insurance

;; Constants
(define-constant admin tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-SHOW-NOT-FOUND (err u101))
(define-constant ERR-NO-SEATS (err u102))
(define-constant ERR-NO-TRANSFERS (err u103))
(define-constant ERR-SHOW-ONGOING (err u104))
(define-constant ERR-REFUND-INVALID (err u105))
(define-constant ERR-INSURANCE-USED (err u106))
(define-constant ERR-BAD-PARAMS (err u107))
(define-constant INSURANCE-RATE u5) ;; 5% of pass price
(define-constant INSURANCE-VAULT 'SP000000000000000000002Q6VF78) ;; Example vault address
(define-constant MIN-FEE u1000) ;; Minimum admission fee
(define-constant MAX-CAPACITY u10000) ;; Maximum passes per show

;; Data Variables
(define-data-var next-show-id uint u1)
(define-data-var next-pass-id uint u1)
(define-data-var insurance-vault uint u0)

;; Data Maps
(define-map Shows
    uint  ;; show-id
    {
        title: (string-ascii 100),
        host: principal,
        max-capacity: uint,
        seats-taken: uint,
        admission-fee: uint,
        showtime: uint,
        is-terminated: bool,
        venue-details: (string-ascii 256)
    }
)

(define-map Passes
    uint  ;; pass-id
    {
        show-id: uint,
        holder: principal,
        is-scanned: bool,
        resold: bool,
        ticket-cost: uint,
        has-protection: bool,
        protection-used: bool,
        seat-info: (string-ascii 256)
    }
)

(define-map ShowPasses
    uint  ;; show-id
    (list 500 uint)  ;; list of pass IDs
)

;; Private Functions
(define-private (is-show-host (show-id uint) (caller principal))
    (let ((show (unwrap! (map-get? Shows show-id) false)))
        (is-eq (get host show) caller)
    )
)

(define-private (calculate-protection-cost (pass-price uint))
    (/ (* pass-price INSURANCE-RATE) u100)
)

(define-private (handle-protection-purchase (protection-cost uint) (host principal))
    (if (> protection-cost u0)
        (begin
            (try! (stx-transfer? protection-cost host INSURANCE-VAULT))
            (var-set insurance-vault (+ (var-get insurance-vault) protection-cost))
            (ok true)
        )
        (ok true)
    )
)

(define-private (validate-show-params (title (string-ascii 100)) 
                                    (max-capacity uint)
                                    (admission-fee uint)
                                    (showtime uint)
                                    (venue-details (string-ascii 256)))
    (and
        (> (len title) u0)
        (<= max-capacity MAX-CAPACITY)
        (> max-capacity u0)
        (>= admission-fee MIN-FEE)
        (> showtime block-height)
        (> (len venue-details) u0)
    )
)

;; Public Functions

;; Create a new show
(define-public (create-show (title (string-ascii 100)) 
                          (max-capacity uint) 
                          (admission-fee uint)
                          (showtime uint)
                          (venue-details (string-ascii 256)))
    (let (
        (show-id (var-get next-show-id))
        (params-valid (validate-show-params title max-capacity admission-fee showtime venue-details))
    )
        (asserts! params-valid ERR-BAD-PARAMS)
        
        (map-set Shows
            show-id
            {
                title: title,
                host: tx-sender,
                max-capacity: max-capacity,
                seats-taken: u0,
                admission-fee: admission-fee,
                showtime: showtime,
                is-terminated: false,
                venue-details: venue-details
            }
        )
        (var-set next-show-id (+ show-id u1))
        (ok show-id)
    )
)

;; Purchase a pass with optional protection
(define-public (buy-pass (show-id uint) (with-protection bool))
    (let (
        (show (unwrap! (map-get? Shows show-id) ERR-SHOW-NOT-FOUND))
        (pass-id (var-get next-pass-id))
        (protection-cost (if with-protection 
                           (calculate-protection-cost (get admission-fee show))
                           u0))
        (total-cost (+ (get admission-fee show) protection-cost))
    )
        (asserts! (< (get seats-taken show) (get max-capacity show)) ERR-NO-SEATS)
        (asserts! (not (get is-terminated show)) ERR-SHOW-ONGOING)
        (asserts! (< block-height (get showtime show)) ERR-BAD-PARAMS)
        
        ;; Process payment
        (try! (stx-transfer? total-cost tx-sender (get host show)))
        
        ;; Handle protection purchase
        (try! (handle-protection-purchase protection-cost (get host show)))
        
        ;; Mint pass
        (map-set Passes
            pass-id
            {
                show-id: show-id,
                holder: tx-sender,
                is-scanned: false,
                resold: false,
                ticket-cost: (get admission-fee show),
                has-protection: with-protection,
                protection-used: false,
                seat-info: (get venue-details show)
            }
        )
        
        ;; Update show records
        (map-set Shows
            show-id
            (merge show { seats-taken: (+ (get seats-taken show) u1) })
        )
        
        ;; Add pass to show's pass list
        (match (map-get? ShowPasses show-id)
            passes (map-set ShowPasses 
                        show-id 
                        (unwrap! (as-max-len? (append passes pass-id) u500) ERR-NO-SEATS))
            (map-set ShowPasses show-id (list pass-id))
        )
        
        (var-set next-pass-id (+ pass-id u1))
        (ok pass-id)
    )
)

;; Transfer pass
(define-public (transfer-pass (pass-id uint) (new-holder principal))
    (let ((pass (unwrap! (map-get? Passes pass-id) ERR-SHOW-NOT-FOUND)))
        (asserts! (is-eq (get holder pass) tx-sender) ERR-UNAUTHORIZED)
        (asserts! (not (get resold pass)) ERR-NO-TRANSFERS)
        
        (map-set Passes
            pass-id
            (merge pass {
                holder: new-holder,
                resold: true
            })
        )
        (ok true)
    )
)

;; Cancel show and enable refunds
(define-public (terminate-show (show-id uint))
    (let ((show (unwrap! (map-get? Shows show-id) ERR-SHOW-NOT-FOUND)))
        (asserts! (is-show-host show-id tx-sender) ERR-UNAUTHORIZED)
        
        (map-set Shows
            show-id
            (merge show { is-terminated: true })
        )
        (ok true)
    )
)

;; Claim refund for canceled show
(define-public (request-refund (pass-id uint))
    (let (
        (pass (unwrap! (map-get? Passes pass-id) ERR-SHOW-NOT-FOUND))
        (show (unwrap! (map-get? Shows (get show-id pass)) ERR-SHOW-NOT-FOUND))
    )
        (asserts! (is-eq (get holder pass) tx-sender) ERR-UNAUTHORIZED)
        (asserts! (get is-terminated show) ERR-REFUND-INVALID)
        
        ;; Process refund
        (try! (stx-transfer? (get ticket-cost pass) 
                           (get host show) 
                           tx-sender))
        
        ;; Mark pass as scanned
        (map-set Passes
            pass-id
            (merge pass { is-scanned: true })
        )
        (ok true)
    )
)

;; Claim protection refund (can be used even if show is not canceled)
(define-public (claim-protection-refund (pass-id uint))
    (let (
        (pass (unwrap! (map-get? Passes pass-id) ERR-SHOW-NOT-FOUND))
    )
        (asserts! (is-eq (get holder pass) tx-sender) ERR-UNAUTHORIZED)
        (asserts! (get has-protection pass) ERR-REFUND-INVALID)
        (asserts! (not (get protection-used pass)) ERR-INSURANCE-USED)
        
        ;; Process protection refund
        (try! (stx-transfer? (get ticket-cost pass) 
                           INSURANCE-VAULT 
                           tx-sender))
        
        ;; Mark protection as used
        (map-set Passes
            pass-id
            (merge pass { 
                protection-used: true,
                is-scanned: true 
            })
        )
        (ok true)
    )
)

;; Validate pass
(define-public (scan-pass (pass-id uint))
    (let ((pass (unwrap! (map-get? Passes pass-id) ERR-SHOW-NOT-FOUND)))
        (asserts! (is-show-host (get show-id pass) tx-sender) ERR-UNAUTHORIZED)
        (asserts! (not (get is-scanned pass)) ERR-REFUND-INVALID)
        
        (map-set Passes
            pass-id
            (merge pass { is-scanned: true })
        )
        (ok true)
    )
)

;; Read-only functions

(define-read-only (get-show (show-id uint))
    (map-get? Shows show-id)
)

(define-read-only (get-pass (pass-id uint))
    (map-get? Passes pass-id)
)

(define-read-only (get-show-passes (show-id uint))
    (map-get? ShowPasses show-id)
)

(define-read-only (get-protection-cost (pass-price uint))
    (calculate-protection-cost pass-price)
)

(define-read-only (get-protection-vault-balance)
    (var-get insurance-vault)
)