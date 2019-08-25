pragma solidity ^0.4.24;

import "./abstracts/BlockRewardBase.sol";
import "./interfaces/IConsensus.sol";
import "./eternal-storage/EternalStorage.sol";
import "./ProxyStorage.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

/**
* @title Contract handling block reward logic
* @author LiorRabin
*/
contract BlockReward is EternalStorage, BlockRewardBase {
  using SafeMath for uint256;

  uint256 public constant DECIMALS = 10 ** 18;

  /**
  * @dev This event will be emitted every block, describing the rewards given
  * @param receivers array of addresses to reward
  * @param rewards array of balance increases corresponding to the receivers array
  */
  event Rewarded(address[] receivers, uint256[] rewards);

  /**
  * @dev This event will be emitted on cycle end, describing the amount of rewards distributed on the cycle
  * @param amount total rewards distributed on this cycle
  */
  event RewardedOnCycle(uint256 amount);

  /**
  * @dev This modifier verifies that msg.sender is the system address (EIP96)
  */
  modifier onlySystem() {
    require(msg.sender == addressStorage[SYSTEM_ADDRESS]);
    _;
  }

  /**
  * @dev This modifier verifies that msg.sender is the owner of the contract
  */
  modifier onlyOwner() {
    require(msg.sender == addressStorage[OWNER]);
    _;
  }

  /**
  * @dev This modifier verifies that msg.sender is the consensus contract
  */
  modifier onlyConsensus() {
    require(msg.sender == ProxyStorage(getProxyStorage()).getConsensus());
    _;
  }

  /**
  * @dev This modifier verifies that msg.sender is a validator
  */
  modifier onlyValidator() {
    require(IConsensus(ProxyStorage(getProxyStorage()).getConsensus()).isValidator(msg.sender));
    _;
  }

  /**
  * @dev Function to be called on contract initialization
  * @param _supply initial total supply
  * @param _inflation yearly inflation rate (percentage)
  */
  function initialize(uint256 _supply, uint256 _blocksPerYear, uint256 _inflation) external onlyOwner {
    require(!isInitialized());
    _setSystemAddress(0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE);
    _setTotalSupply(_supply);
    _initRewardedOnCycle();
    _setBlocksPerYear(_blocksPerYear);
    _setInflation(_inflation);
    _setBlockRewardAmount();
    setInitialized(true);
  }

  /**
  * @dev Function called to produce the reward on each block
  * @param benefactors array of addresses representing benefectors to be considered for reward
  * @param kind array of reward types. We support only arrays with one item and type = 0 (Author - Reward attributed to the block author)
  * See https://wiki.parity.io/Block-Reward-Contract.html
  */
  function reward(address[] benefactors, uint16[] kind) external onlySystem returns (address[], uint256[]) {
    require(benefactors.length == kind.length);
    require(benefactors.length == 1);
    require(kind[0] == 0);

    IConsensus(ProxyStorage(getProxyStorage()).getConsensus()).cycle();

    address[] memory receivers = new address[](benefactors.length);
    uint256[] memory rewards = new uint256[](receivers.length);

    uint256 blockRewardAmount = getBlockRewardAmount();

    _setRewardedOnCycle(getRewardedOnCycle().add(blockRewardAmount));
    _setTotalSupply(getTotalSupply().add(blockRewardAmount));

    receivers[0] = benefactors[0];
    rewards[0] = blockRewardAmount;
    emit Rewarded(receivers, rewards);

    if ((block.number).mod(getBlocksPerYear()) == 0) {
      _setBlockRewardAmount();
    }

    return (receivers, rewards);
  }

  function onCycleEnd() external onlyConsensus {
    _setShouldEmitRewardedOnCycle(true);
  }

  /**
  * @dev Function to be called by validators only to emit RewardedOnCycle event (only if `shouldEmitRewardedOnCycle` returns true)
  */
  function emitRewardedOnCycle() external onlyValidator {
    require(shouldEmitRewardedOnCycle());
    emit RewardedOnCycle(getRewardedOnCycle());
    _setShouldEmitRewardedOnCycle(false);
    _setRewardedOnCycle(0);
  }

  bytes32 internal constant OWNER = keccak256(abi.encodePacked("owner"));
  bytes32 internal constant SYSTEM_ADDRESS = keccak256(abi.encodePacked("SYSTEM_ADDRESS"));
  bytes32 internal constant PROXY_STORAGE = keccak256(abi.encodePacked("proxyStorage"));
  bytes32 internal constant TOTAL_SUPPLY = keccak256(abi.encodePacked("totalSupply"));
  bytes32 internal constant REWARDED_THIS_CYCLE = keccak256(abi.encodePacked("rewardedOnCycle"));
  bytes32 internal constant INFLATION = keccak256(abi.encodePacked("inflation"));
  bytes32 internal constant BLOCKS_PER_YEAR = keccak256(abi.encodePacked("blocksPerYear"));
  bytes32 internal constant BLOCK_REWARD_AMOUNT = keccak256(abi.encodePacked("blockRewardAmount"));
  bytes32 internal constant SHOULD_EMIT_REWARDED_ON_CYCLE = keccak256(abi.encodePacked("shouldEmitRewardedOnCycle"));

  function _setSystemAddress(address _newAddress) private {
    addressStorage[SYSTEM_ADDRESS] = _newAddress;
  }

  function _setTotalSupply(uint256 _supply) private {
    require(_supply >= 0);
    uintStorage[TOTAL_SUPPLY] = _supply;
  }

  function getTotalSupply() public view returns(uint256) {
    return uintStorage[TOTAL_SUPPLY];
  }

  function _initRewardedOnCycle() private {
    _setRewardedOnCycle(0);
  }

  function _setRewardedOnCycle(uint256 _amount) private {
    require(_amount >= 0);
    uintStorage[REWARDED_THIS_CYCLE] = _amount;
  }

  function getRewardedOnCycle() public view returns(uint256) {
    return uintStorage[REWARDED_THIS_CYCLE];
  }

  function _setInflation(uint256 _inflation) private {
    require(_inflation >= 0);
    uintStorage[INFLATION] = _inflation;
  }

  function getInflation() public view returns(uint256) {
    return uintStorage[INFLATION];
  }

  function _setBlocksPerYear(uint256 _blocksPerYear) private {
    uintStorage[BLOCKS_PER_YEAR] = _blocksPerYear;
  }

  function getBlocksPerYear() public view returns(uint256) {
    return uintStorage[BLOCKS_PER_YEAR];
  }

  function _setBlockRewardAmount() private {
    uintStorage[BLOCK_REWARD_AMOUNT] = (getTotalSupply().mul(getInflation().mul(DECIMALS).div(100))).div(getBlocksPerYear()).div(DECIMALS);
  }

  function getBlockRewardAmount() public view returns(uint256) {
    return uintStorage[BLOCK_REWARD_AMOUNT];
  }

  function getProxyStorage() public view returns(address) {
    return addressStorage[PROXY_STORAGE];
  }

  function shouldEmitRewardedOnCycle() public view returns(bool) {
    return boolStorage[SHOULD_EMIT_REWARDED_ON_CYCLE];
  }

  function _setShouldEmitRewardedOnCycle(bool _status) internal {
    boolStorage[SHOULD_EMIT_REWARDED_ON_CYCLE] = _status;
  }
}