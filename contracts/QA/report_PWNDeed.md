## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| ../PWNDeed.sol | e5aaeefd193186cad11a83d9fca5d29c4d990732 |


### Contracts Description Table


|  Contract  |         Type        |       Bases      |                  |                 |
|:----------:|:-------------------:|:----------------:|:----------------:|:---------------:|
|     └      |  **Function Name**  |  **Visibility**  |  **Mutability**  |  **Modifiers**  |
||||||
| **PWNDeed** | Implementation | ERC1155, ERC1155Burnable, Ownable |||
| └ | <Constructor> | Public ❗️ | 🛑  | ERC1155 Ownable |
| └ | mint | External ❗️ | 🛑  | onlyPWN |
| └ | burn | External ❗️ | 🛑  | onlyPWN |
| └ | setOffer | External ❗️ | 🛑  | onlyPWN |
| └ | deleteOffer | External ❗️ | 🛑  | onlyPWN |
| └ | setCredit | External ❗️ | 🛑  | onlyPWN |
| └ | changeStatus | External ❗️ | 🛑  | onlyPWN |
| └ | _beforeTokenTransfer | Internal 🔒 |   | |
| └ | getDeedStatus | Public ❗️ |   |NO❗️ |
| └ | getExpiration | Public ❗️ |   |NO❗️ |
| └ | getBorrower | Public ❗️ |   |NO❗️ |
| └ | getDeedAsset | Public ❗️ |   |NO❗️ |
| └ | getOffers | Public ❗️ |   |NO❗️ |
| └ | getAcceptedOffer | Public ❗️ |   |NO❗️ |
| └ | getDeedID | Public ❗️ |   |NO❗️ |
| └ | getOfferAsset | Public ❗️ |   |NO❗️ |
| └ | toBePaid | Public ❗️ |   |NO❗️ |
| └ | getLender | Public ❗️ |   |NO❗️ |
| └ | setPWN | External ❗️ | 🛑  | onlyOwner |


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |
