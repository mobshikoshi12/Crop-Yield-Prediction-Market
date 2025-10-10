(define-constant err-not-found (err u201))
(define-constant err-unauthorized (err u202))
(define-constant err-insufficient-pool (err u203))
(define-constant err-market-active (err u204))
(define-constant err-already-refunded (err u205))
(define-constant err-invalid-amount (err u206))

(define-data-var pool-balance uint u0)
(define-data-var insurance-fee-rate uint u50)
(define-data-var emergency-threshold uint u4320)

(define-map insured-markets uint {
    total-coverage: uint,
    emergency-declared: bool,
    refund-processed: bool,
    declaration-block: (optional uint)
})

(define-map user-coverage {user: principal, market-id: uint} uint)

(define-trait market-contract-trait
    ((get-market (uint) (response (optional {creator: principal, deadline: uint, resolved: bool, total-higher: uint, total-lower: uint}) uint))
     (get-user-bet (principal uint) (response (optional {amount: uint, claimed: bool}) uint))))

(define-public (contribute-to-pool (amount uint))
    (begin
        (asserts! (> amount u0) err-invalid-amount)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set pool-balance (+ (var-get pool-balance) amount))
        (ok true)))

(define-public (insure-bet (market-id uint) (bet-amount uint))
    (let ((fee (/ (* bet-amount (var-get insurance-fee-rate)) u10000)))
        (asserts! (> bet-amount u0) err-invalid-amount)
        (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))
        (var-set pool-balance (+ (var-get pool-balance) fee))
        (let ((market-data (default-to {total-coverage: u0, emergency-declared: false, refund-processed: false, declaration-block: none}
                                      (map-get? insured-markets market-id))))
            (map-set insured-markets market-id 
                (merge market-data {total-coverage: (+ (get total-coverage market-data) bet-amount)}))
            (map-set user-coverage {user: tx-sender, market-id: market-id} bet-amount)
            (ok fee))))

(define-public (declare-emergency (market-id uint) (market-contract <market-contract-trait>))
    (let ((market-response (contract-call? market-contract get-market market-id)))
        (match market-response
            market-opt (match market-opt
                market (let ((blocks-overdue (- stacks-block-height (get deadline market))))
                    (asserts! (not (get resolved market)) err-market-active)
                    (asserts! (> blocks-overdue (var-get emergency-threshold)) err-unauthorized)
                    (let ((insurance-data (unwrap! (map-get? insured-markets market-id) err-not-found)))
                        (asserts! (not (get emergency-declared insurance-data)) err-already-refunded)
                        (map-set insured-markets market-id
                            (merge insurance-data {
                                emergency-declared: true,
                                declaration-block: (some stacks-block-height)
                            }))
                        (ok true)))
                err-not-found)
            error-code (err error-code))))

(define-public (claim-refund (market-id uint) (market-contract <market-contract-trait>))
    (let ((insurance-data (unwrap! (map-get? insured-markets market-id) err-not-found))
          (coverage (unwrap! (map-get? user-coverage {user: tx-sender, market-id: market-id}) err-not-found)))
        (asserts! (get emergency-declared insurance-data) err-unauthorized)
        (asserts! (not (get refund-processed insurance-data)) err-already-refunded)
        (asserts! (>= (var-get pool-balance) coverage) err-insufficient-pool)
        (var-set pool-balance (- (var-get pool-balance) coverage))
        (map-delete user-coverage {user: tx-sender, market-id: market-id})
        (as-contract (stx-transfer? coverage tx-sender tx-sender))))

(define-read-only (get-pool-balance)
    (var-get pool-balance))

(define-read-only (get-insurance-fee (amount uint))
    (/ (* amount (var-get insurance-fee-rate)) u10000))

(define-read-only (get-market-coverage (market-id uint))
    (map-get? insured-markets market-id))

(define-read-only (get-user-coverage-amount (user principal) (market-id uint))
    (map-get? user-coverage {user: user, market-id: market-id}))
