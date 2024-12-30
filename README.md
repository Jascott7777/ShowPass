# ShowPass: Decentralized Event Ticketing System

ShowPass is a blockchain-based ticketing system built on the Stacks blockchain that enables secure, transparent, and trustless event ticketing with built-in refund protection.

## Features

### Core Functionality
- **Decentralized Ticket Management**: Create and manage event passes as NFTs on the blockchain
- **Secure Transfer System**: Controlled pass transfers with anti-scalping measures
- **Transparent Validation**: On-chain verification of pass authenticity
- **Automated Refunds**: Smart contract-based refund processing for canceled shows

### Protection System
- **Optional Pass Protection**: Buy passes with or without refund protection
- **Flexible Refund Options**: 
  - Standard refunds for canceled shows
  - Protection-based refunds regardless of show status
- **Protection Pool**: Dedicated vault for managing protection funds
- **Configurable Rates**: Adjustable protection premium (currently set at 5%)

## Smart Contract Details

### Constants
- Minimum admission fee: 1000 microSTX
- Maximum capacity per show: 10,000 passes
- Protection premium: 5% of pass price
- Protection vault address: 'SP000000000000000000002Q6VF78'

### Core Functions

#### For Show Hosts
```clarity
(create-show (title (string-ascii 100)) 
            (max-capacity uint) 
            (admission-fee uint)
            (showtime uint)
            (venue-details (string-ascii 256)))
```
- Creates a new show with specified parameters
- Validates all input parameters
- Returns show-id on success

```clarity
(terminate-show (show-id uint))
```
- Cancels a show and enables standard refunds
- Only callable by show host

```clarity
(scan-pass (pass-id uint))
```
- Validates a pass at entry
- Marks pass as used
- Only callable by show host

#### For Pass Holders
```clarity
(buy-pass (show-id uint) (with-protection bool))
```
- Purchases a pass for specified show
- Optional protection coverage
- Handles both pass and protection payments

```clarity
(transfer-pass (pass-id uint) (new-holder principal))
```
- Transfers pass to new holder
- Limited to one transfer per pass

```clarity
(request-refund (pass-id uint))
```
- Claims refund for canceled shows
- Returns original ticket cost

```clarity
(claim-protection-refund (pass-id uint))
```
- Claims protection refund
- Available regardless of show status
- Returns original ticket cost

### Read-Only Functions
- `get-show`: Retrieves show details
- `get-pass`: Retrieves pass details
- `get-show-passes`: Lists all passes for a show
- `get-protection-cost`: Calculates protection cost
- `get-protection-vault-balance`: Shows current protection pool balance

## Error Codes
- `ERR-UNAUTHORIZED (u100)`: Unauthorized access attempt
- `ERR-SHOW-NOT-FOUND (u101)`: Show ID not found
- `ERR-NO-SEATS (u102)`: Show is sold out
- `ERR-NO-TRANSFERS (u103)`: Pass transfer not allowed
- `ERR-SHOW-ONGOING (u104)`: Show is active/not canceled
- `ERR-REFUND-INVALID (u105)`: Invalid refund request
- `ERR-INSURANCE-USED (u106)`: Protection already claimed
- `ERR-BAD-PARAMS (u107)`: Invalid input parameters

## Usage Example

1. Create a new show:
```clarity
(contract-call? .showpass create-show "Summer Concert 2024" u1000 u50000 u80000 "Main Stadium")
```

2. Purchase a pass with protection:
```clarity
(contract-call? .showpass buy-pass u1 true)
```

3. Validate pass at entry:
```clarity
(contract-call? .showpass scan-pass u1)
```

## Security Considerations

1. **Pass Transfers**: Limited to one transfer per pass to prevent scalping
2. **Protection Claims**: Can only be claimed once per pass
3. **Access Control**: Strict validation of host and holder permissions
4. **Parameter Validation**: Comprehensive input validation for all functions

## Development

### Prerequisites
- Clarity CLI
- Stacks blockchain development environment
- STX testnet account for testing

### Testing
Run the test suite:
```bash
clarinet test
```

### Deployment
1. Update constants as needed (protection rate, minimum fee, etc.)
2. Deploy to testnet for initial testing
3. Verify all functions work as expected
4. Deploy to mainnet

## Contributing
1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request


## Disclaimer
This smart contract is provided as-is. Users should perform their own security audits before deployment.