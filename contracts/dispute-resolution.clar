(define-constant err-not-found (err u301))
(define-constant err-unauthorized (err u302))
(define-constant err-already-disputed (err u303))
(define-constant err-insufficient-stake (err u304))
(define-constant err-dispute-expired (err u305))
(define-constant err-already-voted (err u306))
(define-constant err-invalid-amount (err u307))

(define-data-var min-dispute-stake uint u1000000)
(define-data-var dispute-window uint u144)
(define-data-var min-supporters uint u3)

(define-map disputes uint {
    market-id: uint,
    initiator: principal,
    total-stake: uint,
    supporters: uint,
    disputed-yield: uint,
    proposed-yield: uint,
    creation-block: uint,
    resolved: bool,
    upheld: bool
})

(define-map dispute-votes {dispute-id: uint, voter: principal} uint)

(define-map market-disputes uint (optional uint))

(define-data-var dispute-counter uint u0)

(define-trait market-trait
    ((get-market (uint) (response (optional {creator: principal, deadline: uint, resolved: bool, actual-yield: (optional uint)}) uint))))

(define-public (open-dispute (market-id uint) (proposed-yield uint) (stake-amount uint) (market-contract <market-trait>))
    (let ((market-response (contract-call? market-contract get-market market-id)))
        (match market-response
            market-opt (match market-opt
                market (let ((actual-yield-opt (get actual-yield market)))
                    (asserts! (get resolved market) err-unauthorized)
                    (asserts! (is-none (map-get? market-disputes market-id)) err-already-disputed)
                    (asserts! (>= stake-amount (var-get min-dispute-stake)) err-insufficient-stake)
                    (asserts! (is-some actual-yield-opt) err-not-found)
                    (let ((actual-yield (unwrap-panic actual-yield-opt))
                          (dispute-id (+ (var-get dispute-counter) u1)))
                        (asserts! (not (is-eq actual-yield proposed-yield)) err-invalid-amount)
                        (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
                        (map-set disputes dispute-id {
                            market-id: market-id,
                            initiator: tx-sender,
                            total-stake: stake-amount,
                            supporters: u1,
                            disputed-yield: actual-yield,
                            proposed-yield: proposed-yield,
                            creation-block: stacks-block-height,
                            resolved: false,
                            upheld: false
                        })
                        (map-set market-disputes market-id (some dispute-id))
                        (map-set dispute-votes {dispute-id: dispute-id, voter: tx-sender} stake-amount)
                        (var-set dispute-counter dispute-id)
                        (ok dispute-id)))
                err-not-found)
            error-code (err error-code))))

(define-public (support-dispute (dispute-id uint) (stake-amount uint))
    (let ((dispute (unwrap! (map-get? disputes dispute-id) err-not-found))
          (existing-vote (map-get? dispute-votes {dispute-id: dispute-id, voter: tx-sender})))
        (asserts! (is-none existing-vote) err-already-voted)
        (asserts! (not (get resolved dispute)) err-dispute-expired)
        (asserts! (> stake-amount u0) err-invalid-amount)
        (let ((blocks-elapsed (- stacks-block-height (get creation-block dispute))))
            (asserts! (< blocks-elapsed (var-get dispute-window)) err-dispute-expired)
            (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
            (map-set disputes dispute-id 
                (merge dispute {
                    total-stake: (+ (get total-stake dispute) stake-amount),
                    supporters: (+ (get supporters dispute) u1)
                }))
            (map-set dispute-votes {dispute-id: dispute-id, voter: tx-sender} stake-amount)
            (ok true))))

(define-public (resolve-dispute (dispute-id uint) (upheld bool))
    (let ((dispute (unwrap! (map-get? disputes dispute-id) err-not-found)))
        (asserts! (not (get resolved dispute)) err-already-disputed)
        (let ((blocks-elapsed (- stacks-block-height (get creation-block dispute))))
            (asserts! (>= blocks-elapsed (var-get dispute-window)) err-unauthorized)
            (map-set disputes dispute-id (merge dispute {resolved: true, upheld: upheld}))
            (ok true))))

(define-read-only (get-dispute (dispute-id uint))
    (map-get? disputes dispute-id))

(define-read-only (get-market-dispute-id (market-id uint))
    (map-get? market-disputes market-id))

(define-read-only (get-user-vote (dispute-id uint) (voter principal))
    (map-get? dispute-votes {dispute-id: dispute-id, voter: voter}))

(define-read-only (get-dispute-status (dispute-id uint))
    (match (map-get? disputes dispute-id)
        dispute (ok {
            active: (not (get resolved dispute)),
            supporters: (get supporters dispute),
            total-staked: (get total-stake dispute),
            threshold-met: (>= (get supporters dispute) (var-get min-supporters))
        })
        err-not-found))
