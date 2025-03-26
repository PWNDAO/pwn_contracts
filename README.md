# PWN Protocol

PWN is a protocol that enables peer-to-peer (P2P) loans using arbitrary collateral. Our smart contracts support ERC20, ERC721, and ERC1155 standards, making it versatile and adaptable to a wide range of use cases.

## About

In the world of decentralized finance, PWN stands out with its unique approach to P2P loans. By allowing users to leverage different types of collateral, we provide flexibility and convenience that's unmatched in the industry.

## Developer Documentation

For developers interested in integrating with or building on top of PWN, we provide comprehensive documentation. You can find in-depth information about our smart contracts and their usage in the [PWN Developer Docs](https://dev-docs.pwn.xyz/).

## Deployment

| Name                                   | Address                                    |
|----------------------------------------|--------------------------------------------|
| Config                                 | 0xd52a2898d61636bB3eEF0d145f05352FF543bdCC |
| Hub                                    | 0x37807A2F031b3B44081F4b21500E5D70EbaDAdd5 |
| LOAN Token                             | 0x4440C069272cC34b80C7B11bEE657D0349Ba9C23 |
| Revoked Nonce                          | 0x972204fF33348ee6889B2d0A3967dB67d7b08e4c |
| Utilized Credit*                       | 0x8E6F44DEa3c11d69C63655BDEcbA25Fa986BCE9D |
| Simple Loan*                           | 0x719A69d0dc67bd3Aa7648D4694081B3c87952797 |
| Simple Loan Simple Proposal*           | 0xe624E7D33baC728bE2bdB606Da0018B6E05A84D9 |
| Simple Loan List Proposal*             | 0x7160Ec33788Df9AFb8AAEe777e7Ae21151B51eDd |
| Simple Loan Elastic Chainlink Proposal | see [Elastic Chainlink Proposal table](#elastic-chainlink-proposal) |
| Simple Loan Elastic Proposal*          | 0xeC6390D4B22FFfD22E5C5FDB56DaF653C3Cd0626 |
| Simple Loan Dutch Auction Proposal*    | 0x1b1394F436cAeaE139131E9bca6f5d5A2A7e1369 |

Most of the addresses listed in the table above are the same on all deployed chains (addresses with * are different on Unichain only). This means that regardless of the blockchain network you are using, such as Ethereum or Arbitrum, the addresses for the PWN smart contracts remain consistent. This provides a seamless experience for developers and users who want to interact with the PWN protocol across different blockchain ecosystems.

### Elastic Chainlink Proposal
Elastic Chainlink Proposal addresses differ across chains due to unique constructor parameters. Below are the addresses for the Elastic Chainlink Proposal on each supported chain:

| Chain                                  | Address                                    |
|----------------------------------------|--------------------------------------------|
| Ethereum                               | 0xBA58E16BE93dAdcBB74a194bDfD9E5933b24016B |
| Optimism                               | 0x983b0916dBA60F58Ea3E4190549DFD7a0c8aF7b4 |
| Binance Smart Chain                    | 0x2d5F60E96442a45e9E3754412189ACaa3aA1AE3a |
| Gnosis Chain                           | 0x116A5E7A95883973de303122025B4Af23512F315 |
| Unichain                               | --- not deployed ---                       |
| Polygon                                | 0x0FAbfAa5376625F07b954a5ad9b987a6b0f39E8F |
| World Chain                            | --- not deployed ---                       |
| Base                                   | 0x0dFf6CA171A1A7C7dE14826feB823386D82d1b36 |
| Arbitrum                               | 0x3b252fD3B958d03C2861DA045ca8A418E7155234 |
| Linea                                  | 0xEBd31872f39C42dDe954e5182BC4528C388A6a2B |
| Ink                                    | --- not deployed ---                       |
| Sonic                                  | 0x49d08582e9c2871F29BEF73D164bFF8fE90c3557 |
| Sepolia                                | 0x39fd308D651F5add5A4826D12Bf92d9D91E732AC |

Please note that some chains are currently not supported by Chainlink. As a result, the Elastic Chainlink Proposal has not been deployed on these chains. We are closely monitoring the support status and will deploy the necessary contracts as soon as Chainlink becomes available on these networks.


### Unichain Differences

| Name                                   | Address                                    |
|----------------------------------------|--------------------------------------------|
| Utilized Credit                        | 0x585C2D4d5D84b296921BF96598961Eec6Ae5C09C |
| Simple Loan                            | 0x322e86E6c813d77a904C5B4aa808a13E0AD4412f |
| Simple Loan Simple Proposal            | 0xCAec7F837930dC9fB36B0E584FEf498714B2a951 |
| Simple Loan List Proposal              | 0x2ECd36747A4a18Dc578798A79c87035D610EDE9F |
| Simple Loan Elastic Proposal           | 0x2Bf2dC42eF08FA2C5BD15f6aDca402bf2Be75A1A |
| Simple Loan Dutch Auction Proposal     | 0x469B2C01FBb8D2073562F4Fe28aaA67D59c05Dc2 |

### Deployed Chains

PWN is deployed on the following chains:

- Ethereum (1)
- Optimism (10)
- Binance Smart Chain (56)
- Gnosis Chain (100)
- Unichain (130)
- Polygon (137)
- Sonic (146)
- World Chain (480)
- Base (8453)
- Arbitrum (42161)
- Ink (57073)
- Linea (59144)
- Sepolia (11155111)

## Contributing

We welcome contributions from the community. If you're a developer interested in contributing to PWN, please see our developer docs for more information.

## PWN is Hiring!

We're always looking for talented individuals to join our team. If you're passionate about decentralized finance and want to contribute to the future of P2P lending, check out our job postings [here](https://www.notion.so/PWN-is-hiring-f5a49899369045e39f41fc7e4c7b5633).

## Contact

If you have any questions or suggestions, feel free to reach out to us. We're always happy to hear from our users.
