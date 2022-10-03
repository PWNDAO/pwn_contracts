## Sūrya's Description Report

### Files Description Table


|  File Name  |  SHA-1 Hash  |
|-------------|--------------|
| ../PWNDeed.sol | fcfbc0cd5122bca19feb7b24a6ff24c1d138d8f3 |


### Contracts Description Table


|  Contract  |         Type        |       Bases      |                  |                 |
|:----------:|:-------------------:|:----------------:|:----------------:|:---------------:|
|     └      |  **Function Name**  |  **Visibility**  |  **Mutability**  |  **Modifiers**  |
||||||
| **PWNDeed** | Implementation | ERC1155, Ownable |||
| └ | <Constructor> | Public ❗️ | 🛑  | ERC1155 Ownable |
| └ | create | External ❗️ | 🛑  | onlyPWN |
| └ | revoke | External ❗️ | 🛑  | onlyPWN |
| └ | makeOffer | External ❗️ | 🛑  | onlyPWN |
| └ | revokeOffer | External ❗️ | 🛑  | onlyPWN |
| └ | acceptOffer | External ❗️ | 🛑  | onlyPWN |
| └ | repayLoan | External ❗️ | 🛑  | onlyPWN |
| └ | claim | External ❗️ | 🛑  | onlyPWN |
| └ | burn | External ❗️ | 🛑  | onlyPWN |
| └ | getDeedStatus | Public ❗️ |   |NO❗️ |
| └ | getExpiration | Public ❗️ |   |NO❗️ |
| └ | getDuration | Public ❗️ |   |NO❗️ |
| └ | getBorrower | Public ❗️ |   |NO❗️ |
| └ | getDeedCollateral | Public ❗️ |   |NO❗️ |
| └ | getOffers | Public ❗️ |   |NO❗️ |
| └ | getAcceptedOffer | Public ❗️ |   |NO❗️ |
| └ | getDeedID | Public ❗️ |   |NO❗️ |
| └ | getOfferLoan | Public ❗️ |   |NO❗️ |
| └ | toBePaid | Public ❗️ |   |NO❗️ |
| └ | getLender | Public ❗️ |   |NO❗️ |
| └ | setPWN | External ❗️ | 🛑  | onlyOwner |
| └ | setUri | External ❗️ | 🛑  | onlyOwner |


### Legend

|  Symbol  |  Meaning  |
|:--------:|-----------|
|    🛑    | Function can modify state |
|    💵    | Function is payable |
