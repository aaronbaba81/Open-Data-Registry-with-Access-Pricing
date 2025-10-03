# 📊 Open Data Registry with Access Pricing

A Clarity smart contract that enables researchers to publish datasets on-chain with usage license rules and dynamic pricing mechanisms.

## 🚀 Features

- **Dataset Registration**: Researchers can register datasets with metadata, pricing, and license terms
- **Dynamic Pricing**: Prices adjust based on demand and access frequency
- **Access Control**: Time-based access licensing with expiration
- **Payment System**: Built-in deposit/withdrawal mechanism for seamless transactions
- **Revenue Sharing**: Platform fees automatically distributed between dataset owners and platform

## 📋 Contract Functions

### 🔍 Read-Only Functions

- `get-dataset(dataset-id)` - Retrieve dataset information
- `get-user-access(dataset-id, user)` - Check user's access status
- `get-user-balance(user)` - Get user's account balance
- `get-current-price(dataset-id)` - Get current dynamic price
- `has-valid-access(dataset-id, user)` - Check if access is still valid

### ✍️ Public Functions

- `register-dataset(title, description, data-hash, base-price, license-type)` - Register a new dataset
- `purchase-access(dataset-id, duration)` - Purchase access to a dataset
- `deposit-funds(amount)` - Deposit STX tokens to your account
- `withdraw-funds(amount)` - Withdraw STX tokens from your account
- `update-dataset-status(dataset-id, is-active)` - Enable/disable dataset (owner only)
- `update-base-price(dataset-id, new-price)` - Update dataset base price (owner only)
- `set-platform-fee(new-fee)` - Set platform fee percentage (contract owner only)

## 🛠️ Usage Instructions

### 1. Deploy the Contract
```bash
clarinet check
clarinet test
clarinet integrate
```

### 2. Register a Dataset
```clarity
(contract-call? .Open-Data-Registry-with-Access-Pricing register-dataset
  "Climate Data 2024"
  "Temperature and precipitation data for North America"
  "abc123def456..."
  u1000000
  "CC-BY-4.0"
)
```

### 3. Deposit Funds
```clarity
(contract-call? .Open-Data-Registry-with-Access-Pricing deposit-funds u5000000)
```

### 4. Purchase Access
```clarity
(contract-call? .Open-Data-Registry-with-Access-Pricing purchase-access u1 u144)
```

### 5. Check Access Status
```clarity
(contract-call? .Open-Data-Registry-with-Access-Pricing has-valid-access u1 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

## 💰 Pricing Model

- **Base Price**: Set by dataset owner
- **Dynamic Multiplier**: Increases with popularity (5% per 10 accesses)
- **Platform Fee**: Configurable percentage (default 5%)
- **Duration**: Access length affects total cost

## 🔐 Security Features

- Owner-only functions for dataset management
- Balance checks prevent overspending
- Time-based access expiration
- Hash-based dataset integrity

## 📈 Dynamic Pricing Algorithm

The contract implements a simple demand-based pricing model:
- Base multiplier: 100% (no change)
- After 10 accesses: 105% of base price
- After 20 accesses: 110% of base price
- And so on...

## 🧪 Testing

Run the test suite:
```bash
clarinet test
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📜 License

This project is licensed under the MIT License.

## 🛡️ Error Codes

- `u100`: Owner-only function
- `u101`: Dataset not found
- `u102`: Insufficient payment
- `u103`: Unauthorized access
- `u104`: Dataset already exists
- `u105`: Invalid price

---

Built with ❤️ using Clarity and Stacks blockchain
