(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-dataset-not-found (err u101))
(define-constant err-insufficient-payment (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-dataset-exists (err u104))
(define-constant err-invalid-price (err u105))

(define-constant err-already-rated (err u106))
(define-constant err-invalid-rating (err u107))
(define-constant err-no-access-history (err u108))

(define-constant err-subscription-not-found (err u109))
(define-constant err-subscription-exists (err u110))
(define-constant err-subscription-expired (err u111))
(define-constant err-invalid-plan (err u112))

(define-constant err-invalid-referral (err u113))
(define-constant err-self-referral (err u114))
(define-constant referral-reward-percentage u200)

(define-constant err-bundle-not-found (err u115))
(define-constant err-bundle-exists (err u116))
(define-constant err-not-dataset-owner (err u117))
(define-constant err-invalid-bundle-size (err u118))

(define-data-var next-bundle-id uint u1)

(define-data-var next-dataset-id uint u1)
(define-data-var platform-fee uint u50)

(define-map datasets
  uint
  {
    owner: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    data-hash: (string-ascii 64),
    base-price: uint,
    access-count: uint,
    created-at: uint,
    license-type: (string-ascii 50),
    is-active: bool
  }
)

(define-map dataset-access
  { dataset-id: uint, user: principal }
  {
    purchased-at: uint,
    expires-at: uint,
    access-level: (string-ascii 20)
  }
)

(define-map user-balances
  principal
  uint
)

(define-map pricing-multipliers
  uint
  uint
)

(define-read-only (get-dataset (dataset-id uint))
  (map-get? datasets dataset-id)
)

(define-read-only (get-user-access (dataset-id uint) (user principal))
  (map-get? dataset-access { dataset-id: dataset-id, user: user })
)

(define-read-only (get-user-balance (user principal))
  (default-to u0 (map-get? user-balances user))
)

(define-read-only (get-current-price (dataset-id uint))
  (match (map-get? datasets dataset-id)
    dataset-info
    (let (
      (base-price (get base-price dataset-info))
      (access-count (get access-count dataset-info))
      (multiplier (default-to u100 (map-get? pricing-multipliers dataset-id)))
    )
    (/ (* base-price multiplier) u100)
    )
    u0
  )
)

(define-read-only (get-platform-fee)
  (var-get platform-fee)
)

(define-read-only (has-valid-access (dataset-id uint) (user principal))
  (match (map-get? dataset-access { dataset-id: dataset-id, user: user })
    access-info
    (> (get expires-at access-info) stacks-block-height)
    false
  )
)

(define-public (register-dataset (title (string-ascii 100)) (description (string-ascii 500)) (data-hash (string-ascii 64)) (base-price uint) (license-type (string-ascii 50)))
  (let (
    (dataset-id (var-get next-dataset-id))
  )
  (asserts! (> base-price u0) err-invalid-price)
  (asserts! (is-none (map-get? datasets dataset-id)) err-dataset-exists)
  (map-set datasets dataset-id {
    owner: tx-sender,
    title: title,
    description: description,
    data-hash: data-hash,
    base-price: base-price,
    access-count: u0,
    created-at: stacks-block-height,
    license-type: license-type,
    is-active: true
  })
  (var-set next-dataset-id (+ dataset-id u1))
  (map-set pricing-multipliers dataset-id u100)
  (ok dataset-id)
  )
)

(define-public (purchase-access (dataset-id uint) (duration uint))
  (let (
    (dataset-info (unwrap! (map-get? datasets dataset-id) err-dataset-not-found))
    (current-price (get-current-price dataset-id))
    (total-cost current-price)
    (user-balance (get-user-balance tx-sender))
    (platform-fee-amount (/ (* total-cost (var-get platform-fee)) u1000))
    (owner-payment (- total-cost platform-fee-amount))
  )
  (asserts! (get is-active dataset-info) err-dataset-not-found)
  (asserts! (>= user-balance total-cost) err-insufficient-payment)
  (map-set user-balances tx-sender (- user-balance total-cost))
  (map-set user-balances (get owner dataset-info) 
    (+ (get-user-balance (get owner dataset-info)) owner-payment))
  (map-set user-balances contract-owner 
    (+ (get-user-balance contract-owner) platform-fee-amount))
  (map-set dataset-access { dataset-id: dataset-id, user: tx-sender } {
    purchased-at: stacks-block-height,
    expires-at: (+ stacks-block-height duration),
    access-level: "full"
  })
  (map-set datasets dataset-id 
    (merge dataset-info { access-count: (+ (get access-count dataset-info) u1) }))
  (try! (update-pricing-multiplier dataset-id))
  (ok true)
  )
)

(define-public (deposit-funds (amount uint))
  (begin
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set user-balances tx-sender (+ (get-user-balance tx-sender) amount))
    (ok true)
  )
)

(define-public (withdraw-funds (amount uint))
  (let (
    (user-balance (get-user-balance tx-sender))
  )
  (asserts! (>= user-balance amount) err-insufficient-payment)
  (map-set user-balances tx-sender (- user-balance amount))
  (as-contract (stx-transfer? amount tx-sender tx-sender))
  )
)

(define-public (update-dataset-status (dataset-id uint) (is-active bool))
  (let (
    (dataset-info (unwrap! (map-get? datasets dataset-id) err-dataset-not-found))
  )
  (asserts! (is-eq tx-sender (get owner dataset-info)) err-unauthorized)
  (map-set datasets dataset-id (merge dataset-info { is-active: is-active }))
  (ok true)
  )
)

(define-public (update-base-price (dataset-id uint) (new-price uint))
  (let (
    (dataset-info (unwrap! (map-get? datasets dataset-id) err-dataset-not-found))
  )
  (asserts! (is-eq tx-sender (get owner dataset-info)) err-unauthorized)
  (asserts! (> new-price u0) err-invalid-price)
  (map-set datasets dataset-id (merge dataset-info { base-price: new-price }))
  (ok true)
  )
)

(define-public (set-platform-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-fee u100) err-invalid-price)
    (var-set platform-fee new-fee)
    (ok true)
  )
)

(define-private (update-pricing-multiplier (dataset-id uint))
  (let (
    (dataset-info (unwrap! (map-get? datasets dataset-id) err-dataset-not-found))
    (access-count (get access-count dataset-info))
    (new-multiplier (if (> access-count u10) 
      (+ u100 (* access-count u5)) 
      u100))
  )
  (map-set pricing-multipliers dataset-id new-multiplier)
  (ok true)
  ) 
)


(define-map dataset-ratings
  { dataset-id: uint, user: principal }
  {
    rating: uint,
    review: (string-ascii 200),
    submitted-at: uint
  }
)

(define-map dataset-rating-stats
  uint
  {
    total-ratings: uint,
    sum-ratings: uint,
    average-rating: uint
  }
)

(define-read-only (get-dataset-rating (dataset-id uint))
  (default-to 
    { total-ratings: u0, sum-ratings: u0, average-rating: u0 }
    (map-get? dataset-rating-stats dataset-id)
  )
)

(define-read-only (get-user-rating (dataset-id uint) (user principal))
  (map-get? dataset-ratings { dataset-id: dataset-id, user: user })
)

(define-public (rate-dataset (dataset-id uint) (rating uint) (review (string-ascii 200)))
  (let (
    (dataset-info (unwrap! (map-get? datasets dataset-id) err-dataset-not-found))
    (user-access (unwrap! (map-get? dataset-access { dataset-id: dataset-id, user: tx-sender }) err-no-access-history))
    (existing-rating (map-get? dataset-ratings { dataset-id: dataset-id, user: tx-sender }))
    (current-stats (get-dataset-rating dataset-id))
  )
  (asserts! (is-none existing-rating) err-already-rated)
  (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
  (map-set dataset-ratings { dataset-id: dataset-id, user: tx-sender } {
    rating: rating,
    review: review,
    submitted-at: stacks-block-height
  })
  (let (
    (new-total (+ (get total-ratings current-stats) u1))
    (new-sum (+ (get sum-ratings current-stats) rating))
    (new-average (/ (* new-sum u100) new-total))
  )
  (map-set dataset-rating-stats dataset-id {
    total-ratings: new-total,
    sum-ratings: new-sum,
    average-rating: new-average
  })
  )
  (ok true)
  )
)


(define-map subscription-plans
  { dataset-id: uint, plan-type: (string-ascii 20) }
  {
    price-per-period: uint,
    period-duration: uint,
    max-subscribers: uint,
    current-subscribers: uint,
    is-active: bool
  }
)

(define-map user-subscriptions
  { dataset-id: uint, user: principal }
  {
    plan-type: (string-ascii 20),
    subscribed-at: uint,
    last-payment: uint,
    next-payment-due: uint,
    auto-renew: bool,
    is-active: bool
  }
)

(define-read-only (get-subscription-plan (dataset-id uint) (plan-type (string-ascii 20)))
  (map-get? subscription-plans { dataset-id: dataset-id, plan-type: plan-type })
)

(define-read-only (get-user-subscription (dataset-id uint) (user principal))
  (map-get? user-subscriptions { dataset-id: dataset-id, user: user })
)

(define-read-only (has-active-subscription (dataset-id uint) (user principal))
  (match (map-get? user-subscriptions { dataset-id: dataset-id, user: user })
    sub-info
    (and (get is-active sub-info) (> (get next-payment-due sub-info) stacks-block-height))
    false
  )
)

(define-public (create-subscription-plan (dataset-id uint) (plan-type (string-ascii 20)) (price-per-period uint) (period-duration uint) (max-subscribers uint))
  (let (
    (dataset-info (unwrap! (map-get? datasets dataset-id) err-dataset-not-found))
  )
  (asserts! (is-eq tx-sender (get owner dataset-info)) err-unauthorized)
  (asserts! (> price-per-period u0) err-invalid-price)
  (asserts! (> period-duration u0) err-invalid-plan)
  (map-set subscription-plans { dataset-id: dataset-id, plan-type: plan-type } {
    price-per-period: price-per-period,
    period-duration: period-duration,
    max-subscribers: max-subscribers,
    current-subscribers: u0,
    is-active: true
  })
  (ok true)
  )
)

(define-public (subscribe-to-dataset (dataset-id uint) (plan-type (string-ascii 20)) (auto-renew bool))
  (let (
    (plan (unwrap! (map-get? subscription-plans { dataset-id: dataset-id, plan-type: plan-type }) err-invalid-plan))
    (user-balance (get-user-balance tx-sender))
    (subscription-cost (get price-per-period plan))
    (existing-sub (map-get? user-subscriptions { dataset-id: dataset-id, user: tx-sender }))
  )
  (asserts! (get is-active plan) err-invalid-plan)
  (asserts! (is-none existing-sub) err-subscription-exists)
  (asserts! (< (get current-subscribers plan) (get max-subscribers plan)) err-invalid-plan)
  (asserts! (>= user-balance subscription-cost) err-insufficient-payment)
  (map-set user-balances tx-sender (- user-balance subscription-cost))
  (map-set user-subscriptions { dataset-id: dataset-id, user: tx-sender } {
    plan-type: plan-type,
    subscribed-at: stacks-block-height,
    last-payment: stacks-block-height,
    next-payment-due: (+ stacks-block-height (get period-duration plan)),
    auto-renew: auto-renew,
    is-active: true
  })
  (map-set subscription-plans { dataset-id: dataset-id, plan-type: plan-type }
    (merge plan { current-subscribers: (+ (get current-subscribers plan) u1) }))
  (ok true)
  )
)

(define-public (cancel-subscription (dataset-id uint))
  (let (
    (subscription (unwrap! (map-get? user-subscriptions { dataset-id: dataset-id, user: tx-sender }) err-subscription-not-found))
    (plan (unwrap! (map-get? subscription-plans { dataset-id: dataset-id, plan-type: (get plan-type subscription) }) err-invalid-plan))
  )
  (map-set user-subscriptions { dataset-id: dataset-id, user: tx-sender }
    (merge subscription { auto-renew: false, is-active: false }))
  (map-set subscription-plans { dataset-id: dataset-id, plan-type: (get plan-type subscription) }
    (merge plan { current-subscribers: (- (get current-subscribers plan) u1) }))
  (ok true)
  )
)

(define-map referral-codes
  principal
  {
    code: (string-ascii 20),
    total-referrals: uint,
    total-earnings: uint,
    is-active: bool
  }
)

(define-map referral-relationships
  { dataset-id: uint, buyer: principal }
  {
    referrer: principal,
    reward-paid: uint,
    purchased-at: uint
  }
)

(define-read-only (get-referral-code (user principal))
  (map-get? referral-codes user)
)

(define-read-only (get-referral-stats (user principal))
  (default-to 
    { code: "", total-referrals: u0, total-earnings: u0, is-active: false }
    (map-get? referral-codes user)
  )
)

(define-public (create-referral-code (code (string-ascii 20)))
  (begin
    (asserts! (is-none (map-get? referral-codes tx-sender)) err-dataset-exists)
    (map-set referral-codes tx-sender {
      code: code,
      total-referrals: u0,
      total-earnings: u0,
      is-active: true
    })
    (ok true)
  )
)

(define-public (purchase-with-referral (dataset-id uint) (duration uint) (referrer principal))
  (let (
    (dataset-info (unwrap! (map-get? datasets dataset-id) err-dataset-not-found))
    (current-price (get-current-price dataset-id))
    (user-balance (get-user-balance tx-sender))
    (platform-fee-amount (/ (* current-price (var-get platform-fee)) u1000))
    (referral-reward (/ (* platform-fee-amount referral-reward-percentage) u1000))
    (platform-net-fee (- platform-fee-amount referral-reward))
    (owner-payment (- current-price platform-fee-amount))
    (referrer-info (unwrap! (map-get? referral-codes referrer) err-invalid-referral))
  )
  (asserts! (get is-active dataset-info) err-dataset-not-found)
  (asserts! (not (is-eq tx-sender referrer)) err-self-referral)
  (asserts! (get is-active referrer-info) err-invalid-referral)
  (asserts! (has-valid-access dataset-id referrer) err-invalid-referral)
  (asserts! (>= user-balance current-price) err-insufficient-payment)
  (map-set user-balances tx-sender (- user-balance current-price))
  (map-set user-balances (get owner dataset-info) 
    (+ (get-user-balance (get owner dataset-info)) owner-payment))
  (map-set user-balances contract-owner 
    (+ (get-user-balance contract-owner) platform-net-fee))
  (map-set user-balances referrer 
    (+ (get-user-balance referrer) referral-reward))
  (map-set dataset-access { dataset-id: dataset-id, user: tx-sender } {
    purchased-at: stacks-block-height,
    expires-at: (+ stacks-block-height duration),
    access-level: "full"
  })
  (map-set datasets dataset-id 
    (merge dataset-info { access-count: (+ (get access-count dataset-info) u1) }))
  (map-set referral-codes referrer
    (merge referrer-info { 
      total-referrals: (+ (get total-referrals referrer-info) u1),
      total-earnings: (+ (get total-earnings referrer-info) referral-reward)
    }))
  (map-set referral-relationships { dataset-id: dataset-id, buyer: tx-sender } {
    referrer: referrer,
    reward-paid: referral-reward,
    purchased-at: stacks-block-height
  })
  (try! (update-pricing-multiplier dataset-id))
  (ok true)
  )
)

(define-map dataset-bundles
  uint
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-ascii 300),
    discount-percentage: uint,
    is-active: bool,
    created-at: uint,
    total-purchases: uint
  }
)

(define-map bundle-datasets
  { bundle-id: uint, dataset-id: uint }
  bool
)

(define-map bundle-purchases
  { bundle-id: uint, user: principal }
  {
    purchased-at: uint,
    total-paid: uint
  }
)

(define-read-only (get-bundle (bundle-id uint))
  (map-get? dataset-bundles bundle-id)
)

(define-read-only (is-dataset-in-bundle (bundle-id uint) (dataset-id uint))
  (default-to false (map-get? bundle-datasets { bundle-id: bundle-id, dataset-id: dataset-id }))
)

(define-read-only (get-bundle-price (bundle-id uint) (dataset-list (list 10 uint)))
  (fold calculate-bundle-total dataset-list { total: u0, discount: u0, valid: true })
)

(define-private (calculate-bundle-total (dataset-id uint) (acc { total: uint, discount: uint, valid: bool }))
  (if (get valid acc)
    (let (
      (price (get-current-price dataset-id))
    )
    { total: (+ (get total acc) price), discount: (get discount acc), valid: true }
    )
    acc
  )
)

(define-public (create-bundle (title (string-ascii 100)) (description (string-ascii 300)) (dataset-list (list 10 uint)) (discount-percentage uint))
  (let (
    (bundle-id (var-get next-bundle-id))
  )
  (asserts! (and (>= discount-percentage u5) (<= discount-percentage u50)) err-invalid-price)
  (asserts! (> (len dataset-list) u1) err-invalid-bundle-size)
  (asserts! (fold check-dataset-owner dataset-list true) err-not-dataset-owner)
  (map-set dataset-bundles bundle-id {
    creator: tx-sender,
    title: title,
    description: description,
    discount-percentage: discount-percentage,
    is-active: true,
    created-at: stacks-block-height,
    total-purchases: u0
  })
  (begin
    (fold register-dataset-to-bundle dataset-list bundle-id)
    (var-set next-bundle-id (+ bundle-id u1))
  )
  (ok bundle-id)
  )
)

(define-private (check-dataset-owner (dataset-id uint) (is-valid bool))
  (if is-valid
    (match (map-get? datasets dataset-id)
      dataset-info
      (is-eq tx-sender (get owner dataset-info))
      false
    )
    false
  )
)

(define-private (register-dataset-to-bundle (dataset-id uint) (bundle-id uint))
  (begin
    (map-set bundle-datasets { bundle-id: bundle-id, dataset-id: dataset-id } true)
    bundle-id
  )
)

(define-public (purchase-bundle (bundle-id uint) (dataset-list (list 10 uint)) (duration uint))
  (let (
    (bundle-info (unwrap! (map-get? dataset-bundles bundle-id) err-bundle-not-found))
    (base-total (fold sum-dataset-prices dataset-list u0))
    (discount-amount (/ (* base-total (get discount-percentage bundle-info)) u100))
    (final-price (- base-total discount-amount))
    (user-balance (get-user-balance tx-sender))
  )
  (asserts! (get is-active bundle-info) err-bundle-not-found)
  (asserts! (>= user-balance final-price) err-insufficient-payment)
  (map-set user-balances tx-sender (- user-balance final-price))
  (fold grant-single-access dataset-list duration)
  (map-set bundle-purchases { bundle-id: bundle-id, user: tx-sender } {
    purchased-at: stacks-block-height,
    total-paid: final-price
  })
  (map-set dataset-bundles bundle-id 
    (merge bundle-info { total-purchases: (+ (get total-purchases bundle-info) u1) }))
  (ok final-price)
  )
)

(define-private (sum-dataset-prices (dataset-id uint) (total uint))
  (+ total (get-current-price dataset-id))
)

(define-private (grant-single-access (dataset-id uint) (dur uint))
  (begin
    (map-set dataset-access { dataset-id: dataset-id, user: tx-sender } {
      purchased-at: stacks-block-height,
      expires-at: (+ stacks-block-height dur),
      access-level: "bundle"
    })
    dur
  )
)
