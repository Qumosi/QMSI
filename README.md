# Spend ERC-20 Create ERC-721 (QMSI Fork)

This is a fork of @fulldecent's https://fulldecent.github.io/spend-ERC20-create-ERC721/

This smart contract is what powers https://qumosi.com/
To interact with the smart contract directly, visit https://qmosi.com/ 

The following are promises this ERC20 smart contract aims to accomplish:
1. QMSI-ERC20 contract has an immutable max supply
2. Users are able to mint ERC721 certificates using QMSI-ERC20 interface on any QMSI-ERC721
3. Users are able to buy ERC721 certificates using QMSI-ERC20 interface on any QMSI-ERC721
4. Users are able to burn their own QMSI-ERC20 tokens
5. Users are able to lock their own QMSI-ERC20 tokens to reclaim burned tokens by trading time
6. Users are able to set allowances and transfer tokens
7. Users are able to link their Qumosi.com profile
8. Users are able to earn free QMSI-ERC20 tokens by drinking from a faucet that rewards using a negative decay formula (`e^(-1/100)`) while simultaneously influenced by halving events
9. Users are able to earn QMSI-ERC20 via commissions collected from QMSI-ERC721 transacted
10. QMSI-ERC20 holds a one to many relationship with QMSI-ERC721 variants with no pre-approvals required
11. QMSI-ERC20 can sustain its remaining state changing supply after faucet runs dry

The following are promises this ERC721 smart contract aims to accomplish:
1. Contract owner deploys QMSI-ERC721 contract with ability to set cost of minting certificate
2. Contract owner can bridge many ERC721 smart contracts to single QMSI-ERC20 implementation
3. Contract owner may use a "deadman switch" to protect owner role in case of untimely demise
4. Contract owner may set a token URI prefix to all resource links
5. Certificate minting cost is influenced by burn rate based on tokens in circulation and max supply
6. All certificates come with verifiable checksum representing JSON preferred resource
7. All certificates come with a unique token id that increments by 1 each time the `create` function is called successfully
8. Minters are required to set a resource link on ERC721 certificate (token URI)
9. Minters are able to set commission rate on ERC721 certificate (percent integer)
10. Certificate owners are able to sell QMSI-721 for corresponding QMSI-ERC20 tokens
11. Certificate owners are able to approveAll QMSI-ERC721 certificates to another user
12. Certificate owners and approved users are able to transfer QMSI-ERC721 certificates
13. Certificate owners and approved users are able to remove sell listings on QMSI-ERC721 certificates


## Using mainnet
The following contract addresses can be found on the Ethereum mainnet
* QMSI-ERC20: [0x1B06DfdcE22bE46C89ECF43EE72C6D710F4A46fC](https://etherscan.io/address/0x1b06dfdce22be46c89ecf43ee72c6d710f4a46fc#code)
* QMSI-ERC721: [0x83f7D4874780c23A26b97cc02863044d5056618D](https://etherscan.io/address/0x83f7d4874780c23a26b97cc02863044d5056618d#code)

### Using testnet
The following contract addresses can be found on the Goerli testnet
* QMSI-ERC20: [0x8407D89E3EaE3083aC1bC774508Fce0CB0de3E27](https://goerli.etherscan.io/address/0x8407D89E3EaE3083aC1bC774508Fce0CB0de3E27)
* QMSI-ERC721: [0x8aaE0af229785dFC973144c3D88396E9f975C2DB](https://goerli.etherscan.io/address/0x8aaE0af229785dFC973144c3D88396E9f975C2DB)

### Using our site
Install MetaMask and visit https://qumosi.com/register.php to create an account.

Once registered, you may connect your wallet and leverage the smart contract alongside the site's own functionality. 

If you wish to interact with the smart contracts directly, use https://qmosi.com/ (without the "u").

## How does it work

**ERC-721 certificate contract** — This is a standard ERC-721 contract implemented using the [0xcert template](https://github.com/0xcert/ethereum-erc721/tree/master/contracts/tokens) with additional functions:

* `create(bytes32 dataHash, string memory tokenURI_, uint256 tokenPrice_, uint256 commission_, address minter_) returns (uint256)` — Allows anybody to create a certificate (NFT) via the ERC20 contract `crossTokenCreate` function. Causes the side effect of deducting a certain amount of money from the user, payable in ERC-20 tokens. The return value is a serial number. It is called by the ERC20 contract only.
* `hashForToken(uint256 tokenId) view` — Allows anybody to find the data hash for a given serial number.
* `mintingPrice() view` — Returns the mint price influenced by the burn rate.
* `trueMintingPrice() view` — Returns the mint price without influence.
* `mintingCurrency() view` — Returns the currency (ERC-20)

* `setMintingPrice(uint256)` — Allows owner (see [0xcert ownable contract](https://github.com/0xcert/ethereum-utils/blob/master/contracts/ownership/Ownable.sol)) to set price that is later influenced by the burn rate
* `setMintingCurrency(ERC20 contract)`  — Allows owner (see [0xcert ownable contract](https://github.com/0xcert/ethereum-utils/blob/master/contracts/ownership/Ownable.sol)) to set currency
* `setBaseURI(string memory baseURI_)` — Allows the contract owner to set a prefix URI on all resource links. Implemented using [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts/pull/2511/files)
* `setTokenURI(uint256 tokenId, string memory tokenURI)` — Allows minter to set token URI resource link to JSON artifact. Implemented using [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts/pull/2511/files)
* `setTokenCommissionProperty(uint256 tokenId, uint256 percentage_)` — Allows minter to take percentage of proceeds from SoldNFT events

* `setDeadmanSwitch(address kin_, uint256 days_)` — Allows the contract owner to set ownership to transfer to a "kin" address if the number of specified days surpass without this function being called again, in order to reset the timer.
* `claimSwitch()` — Allows the `kin` of the switch to claim it, transferring ownership. Only works if the switch is expired from the time it was set. If switch expires, owner is assumed dead.
* `getKin() view` — Returns the address of the next of kin
* `getExpiry() view` — Returns the expiration timestamp of the switch that allows ownership transfer

* `buyToken(address from, uint256 tokenId)` — Allows transferring ownership of certificate if tokens have been transferred to the owner that made the sell token listing
* `sellToken(uint256 tokenId, uint256 _tokenPrice)` — Allows the certificate owner to sell token by specifying the price in ERC20 units and token id
* `removeListing(uint256 tokenId)` — Allows the certificate owner to remove an existing listing to sell the token by specifying the token id

* `tokenPrice(uint256 tokenId) view` — Returns the price of a certificate, if it is listed for sale
* `tokenMinter(uint256 tokenId) view` — Returns the original minter of a certificate
* `tokenURI(uint256 tokenId) view` — Returns the resource link to the token's (JSON) artifact. Implemented using [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts/pull/2511/files)
* `tokenCommission(uint256 tokenId) view` — Returns the percent token commission rate that is taken by the original minter per SoldNFT event

**ERC-20 token contract** — This is a standard ERC-20 contract implemented using the [OpenZeppelin template](https://github.com/OpenZeppelin/openzeppelin-solidity/tree/master/contracts/token/ERC20) with additional functions:
* `drinkFromFaucet()` — Allows end user to earn QMSI ERC-20 tokens by following negative decay curve for token distribution, reset each day.
* `dailyClaimLimit() view` — Showcases the number of QMSI ERC-20 tokens that are available to claim per day. This number is influenced by the halving events.
* `daysConsumed() view` — Showcases number of days the faucet was used.
* `halvingInterval() view` — Tracks the interval for halving events that slash daily reward limit by 1/2 each time. Each unit for the interval is based off of daysConsumed.
* `rewardPerClaim() view` — Showcases how much potential rewards can be earned by drinking from the faucet. This value changes if another user drinks after its execution. 
* `tokensClaimedToday() view` — Tracks the number of total tokens claimed in the current day. Cannot surpass the daily claim limit. 
* `lastClaim(address) view` — Tracks the last time the user used the faucet via `block.timestamp`.
* `circulatingSupply() view` — Returns the number of tokens that are liquid in addition to tokens that are in either pool (burn or stake). This number can be used to see how many coins have been dispensed by the faucet in total.

* `spend(uint256 value)` — Allows end user to burn their own tokens. It can only be triggered by the user, and is used in minting new certificates.
* `burnPool() view` — Returns the amount of tokens that can be reclaimed through staking. Using the `spend` function increments this pool
* `burnRate() view` — Returns a number 0 to 100 that represents the percentage of tokens in circulation (current supply / max supply)

* `stake(uint256 days_, uint256 value_)` — Allows locking ERC20 tokens for number of days to reclaim some burned tokens as reward
* `unlockTokens()` — Allows unlocking locked ERC20 tokens and reward after the unlock date has reached
* `totalStaked() view` — Returns total number of staked ERC20 tokens
* `lockedBalanceOf(address account) view` — Returns the locked balance of an address that is staking
* `unlockDate(address account) view` — Returns the unlock date for an address that is staking
* `rewardsCalculator(uint256 days_, uint256 value_) view` — Helps estimate proposed reward given by the system

* `crossTokenBuy(address market, address to, uint256 tokenId, uint256 tokenPrice_, uint256 tokenCommission_)` — Allows end user to buy ERC721 certificates that have a listing from any QMSI-721 implementation
* `crossTokenCreate(address market, bytes32 dataHash, string memory tokenURI_, uint256 tokenPrice_, uint256 commission_, uint256 mintingPrice_)` — Allows end user to create ERC721 certificates on any QMSI-721 implementation while enforcing burn rate ontop of minting cost

* `setQNS(uint256 qid)` — Allows end user to set their Qumosi profile ID on the associated wallet
* `getQNS(address account) view` — Returns Qumosi profile ID associated with wallet address

## Contract differences and assumptions
The following are key differences in the smart contract implementation from the original:
* The ERC20 implementation does not use a spender role on corresponding ERC721 contract, it was removed in favor of not allowing the ERC721 implementation the ability to spend any user's tokens
* The ERC20 implementation gives users the ability to burn their own tokens, it was done in favor of giving more control to the user; the old implementation allowed any user with the spender role in addition to the spender ERC721 smart contract(s) to burn any user's tokens
* The ERC20 implementation has no owner role
* The ERC721 implementation has a deadman switch to protect the owner role by transferring ownership to a kin if the switch is not renewed by the owner via a defined time interval
* The ERC20 implementation has burn and stake functions that are assumed to self sustain token supply since no liquidity is lost, only state changed. This does not account for impermanent loss
* The ERC20 implementation has a negative decay formula (`e^(-1/100)`) for awarding users free tokens via a faucet function. Each day the user can claim the faucet once, slowly decreasing the reward each time, reset once each day, influenced by halving intervals that occur every 4 years of faucet usage. The faucet is the only way to introduce new tokens to the supply, not surpassing the maximum limit that is immutable.
* The ERC20 implementation aims to fix the "rice and chessboard" problem in staking by allowing rewards to come from burned tokens only
* The ERC20 implementation requires the user to supply the commission rate and token price when buying a NFT certificate to prevent users from transacting with old information that could have changed (for example, while viewing a webpage and not refreshing it after a change in price or commission)
* The ERC20 implementation requires the user to supply the minting price set by the ERC721 implementation (without the burn rate applied) to prevent users from burning an unidentified amount when minting new certificates (for example, minting a new certificate while not checking to see if the minting price had changed)
* The ERC721 implementation includes a optional commission rate attribute that allows the original minter of the certificate to earn a set percentage of transacted QMSI ERC20 tokens each time the NFT is sold via the `crossTokenBuy` function; this value can change but the buyer is aware of the changes since the percent rate has to be supplied when the buy function is invoked
* The ERC20 implementation allows both buying (`crossTokenBuy`) and minting (`crossTokenCreate`) ERC721 certificates freely with no spender role by taking in a smart contract address parameter `market` that is assumed to have the necessary functions in order to both mint and transfer ownership of the NFT certificates; It was done in favor of allowing merchants to create their own custom but QMSI compliant ERC721 contracts that can interact with the QMSI ERC20 contract without needing approval
* The ERC20 implementation assumes that a malicious ERC721 contract supplied in the `market` parameter of either `crossToken*` functions cannot move ERC20 tokens in an unauthorized fashion without the user's knowledge prior to approving the transaction no matter how it is implemented by a merchant

## How to deploy
Clone this repository and use remix to compile and deploy both .sol source files.

## Attribution

The original https://fulldecent.github.io/spend-ERC20-create-ERC721/ was created by William Entriken. Please visit that repository for more information.

New additions to the smart contract done by [twit:@037](https://twitter.com/037) / [git:@649](https://github.com/649)
