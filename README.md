# Build Your Own Mortgage Protocol: Workshop Guide

Welcome to the "Build Your Own Mortgage Protocol" workshop! This guide will help you get started, set up your environment, and understand the goals and context of the workshop.

## 1. Required Tools

Before starting, make sure you have the following tools installed:

- [**Foundry**](https://book.getfoundry.sh/getting-started/installation): Ethereum development toolkit for smart contract development and testing.
- [**VSCode**](https://code.visualstudio.com/): Recommended code editor for Solidity and smart contract development.
- [**Git**](https://git-scm.com/): For version control and collaboration.

Optional but helpful:
- [Solidity VSCode extension](https://marketplace.visualstudio.com/items?itemName=JuanBlanco.solidity)

## 2. Cloning or Forking the Repository

To participate, you need your own copy of this repository. You can either **fork** it to your GitHub account or **clone** it directly:

### Forking (Recommended)
1. Click the **Fork** button in the top right corner.
2. After forking, clone your fork:
   ```sh
   git clone https://github.com/PWNDAO/pwn_protocol.git
   cd pwn_protocol
   ```

### Cloning Directly
If you do not wish to fork, you can clone the main repository:
```sh
git clone https://github.com/PWNDAO/pwn_protocol.git
cd pwn_protocol
```

## 2.1 Switch to the Workshop Branch

After cloning or forking the repository, make sure to switch to the `eth-prg-workshop` branch to access the workshop materials:

```sh
git checkout eth-prg-workshop
```

This branch contains the latest code and setup for the workshop exercises.

## 2.2 Install Dependencies and Build the Project

After cloning or forking the repository, you need to install all necessary dependencies and build the project. Run the following command in your project directory:

```sh
forge build
```

This will fetch all required dependencies and compile the smart contracts, ensuring your environment is ready for development and testing.

## 3. Workshop Goal

The goal of this workshop is to **build custom PWN modules and hooks** to develop your own mortgage protocol. You will:
- Learn the architecture of the PWN protocol
- Extend the protocol by implementing new modules and hooks
- Develop and test your own mortgage logic

## 4. PWN Protocol Overview

PWN is a modular, permissionless, P2P, lending meta-protocol. Its architecture is designed for flexibility and composability, allowing developers to:
- Create custom modules for interest accrual, default condition, and liquidation process
- Integrate hooks for custom loan creation and repayment logic
- Support a wide range of collateral and proposal types

### PWN Loan Lifecycle

The typical lifecycle of a PWN loan consists of the following stages:

1. **Proposal Creation:**
   - A borrower or lender creates a loan proposal specifying terms such as principal, collateral, interest module, default module, and any custom hooks.
2. **Proposal Matching:**
   - The counterparty (lender or borrower) reviews and accepts the proposal, locking in the terms.
3. **Loan Origination:**
   - Upon acceptance, the loan is originated. Collateral is locked, and the principal is transferred to the borrower.
   - Custom hooks (e.g., Borrower Create Hook) can execute additional logic, such as purchasing a House token.
4. **Loan Repayment:**
   - The borrower repays the loan according to the agreed schedule and interest terms.
   - Repayment hooks (e.g., Lender Repayment Hook) ensure funds are routed to the lender.
5. **Loan Closure or Default:**
   - If the loan is fully repaid, collateral is released to the borrower.
   - If default conditions are met (as defined by the default module), the protocol triggers liquidation or other custom logic.

### The `PWNLoan` Contract

The core of the protocol is the `PWNLoan` contract, which manages the state and logic of each loan. Key responsibilities include:
- Storing loan terms, participants, and status
- Enforcing collateralization and repayment rules
- Integrating with modules for interest calculation, default handling, and liquidation
- Executing hooks for custom behaviors during loan creation and repayment

#### Main Entry Functions
The `PWNLoan` contract exposes several main entry functions for interacting with loans:
- `create`: Initiates a new loan with specified terms, collateral, and modules.
- `repay`: Allows the borrower (or a third party) to repay the loan principal and interest.
- `repayWithCollateral`: Allows the borrower to repay the loan using collateral.
- `claimRepayment`: Enables the lender to claim repayment.
- `liquidate`: Triggers liquidation logic if default conditions are met.
- `liquidateByOwner`: Allows the owner to liquidate a loan if default conditions are met.

#### Reentrancy Guard per Loan ID
To ensure security, the contract implements a reentrancy guard scoped to each loan ID. This prevents reentrant calls on a per-loan basis, allowing safe parallel operations on different loans while protecting each loan's state integrity.

By extending or composing with `PWNLoan`, developers can build advanced lending products, such as the custom mortgage flow in this workshop.

## 4.1 Role of Interest, Default, and Liquidation Modules

PWN protocol achieves flexibility and composability through the use of modules for interest, default, and liquidation logic. These modules are set individually for each loan at the time of loan creation, but once set, they are immutable for the lifetime of the loan.

- **Interest Module:**
  - Defines how interest accrues on the loan (e.g., fixed APR, variable rate).
  - Exposes a view function `interest` that the `PWNLoan` contract calls to calculate the current interest due.

- **Default Module:**
  - Determines the conditions under which a loan is considered in default (e.g., time-based limits, total debt limit).
  - Exposes a view function `isDefaulted` that the `PWNLoan` contract calls to check the loan's default status.

- **Liquidation Module:**
  - Specifies the process for handling collateral if a loan defaults (e.g., auction, direct transfer).
  - Does not expose a view function, as liquidation is not triggered by the `PWNLoan` contract when default conditions are met.

Each module implements an `onLoanCreated` hook to configure itself with the loan's parameters at the time of loan origination. This allows the module to initialize any necessary state or settings specific to the loan.

These modules allow each loan to have custom logic while maintaining security and predictability, as their configuration cannot be changed after loan origination. The `PWNLoan` contract interacts with these modules via their view functions and hooks to enforce the loan's terms throughout its lifecycle.

## 5. Workshop Project Goal: Building a Custom Mortgage Flow

In this workshop, your main objective is to implement a custom mortgage protocol that enables a user to "buy" a House token using borrowed funds. You will achieve this by building and integrating the following components:

- **Proposal Type for Custom Mortgage Loans:**
  - Design and implement a new proposal type that enables users to create and test loans with the custom mortgage flow.
  - Use this proposal type to simulate and validate the end-to-end mortgage process during the workshop.

- **Custom Interest Module:**
  - Recommended: Implement a fixed APR (Annual Percentage Rate) for the first 5 years, followed by a gradual interest rate increase.
  - Optionally, you can experiment with a variable interest module.

- **Custom Default Module:**
  - Recommended: Implement a module where the debt limit decreases over time, reducing the borrower's available credit and managing risk.

- **Borrower Create Hook:**
  - Uses the borrower's funds to purchase a House token (NFT).
  - Transfers the House token to the borrower's address upon successful purchase.

- **Lender Repayment Hook:**
  - Ensures that any repayment made by the borrower is automatically transferred to the lender's address.

- **Optional Extensions:**
  - Build a refinancing Borrower Create Hook to allow for loan refinancing.
  - Explore other interest rate models or additional hooks/modules as time allows.

---

**Happy hacking!**
