;; ShowPass - Decentralized Event Ticketing System
;; Description: Smart contract for minting and managing NFT event tickets with transfer restrictions and refund policies

;; Constants
(define-constant admin tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-SHOW-NOT-FOUND (err u101))
(define-constant ERR-NO-SEATS (err u102))
(define-constant ERR-NO-TRANSFERS (err u103))
(define-constant ERR-SHOW-ONGOING (err u104))
(define-constant ERR-REFUND-INVALID (err u105))

;; Data Variables
(define-data-var next-show-id uint u1)
(define-data-var next-pass-id uint u1)

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

;; Public Functions

;; Create a new show
(define-public (create-show (title (string-ascii 100)) 
                          (max-capacity uint) 
                          (admission-fee uint)
                          (showtime uint)
                          (venue-details (string-ascii 256)))
    (let ((show-id (var-get next-show-id)))
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

;; Purchase a pass
(define-public (buy-pass (show-id uint))
    (let (
        (show (unwrap! (map-get? Shows show-id) ERR-SHOW-NOT-FOUND))
        (pass-id (var-get next-pass-id))
    )
        (asserts! (< (get seats-taken show) (get max-capacity show)) ERR-NO-SEATS)
        (asserts! (not (get is-terminated show)) ERR-SHOW-ONGOING)
        
        ;; Process payment
        (try! (stx-transfer? (get admission-fee show) tx-sender (get host show)))
        
        ;; Mint pass
        (map-set Passes
            pass-id
            {
                show-id: show-id,
                holder: tx-sender,
                is-scanned: false,
                resold: false,
                ticket-cost: (get admission-fee show),
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