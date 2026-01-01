// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "../Nibbstack/ownable.sol";

abstract contract DeadmanSwitch is Ownable {
    // @notice Error handlers
    error Unauthorized(address caller);
    error InvalidRange(uint256 value);

    // @notice Event for when deadman switch is set
    event SetDeadSwitch(address indexed kin_, uint256 indexed days_);

    address public _kin;
    uint256 public _timestamp;
    constructor() {
        _kin = msg.sender;
        _timestamp = block.timestamp;
    }

    /**
    * @notice to be used by contract owner to set a deadman switch in the event of worse case scenario
    * @param kin_ the address of the next owner of the smart contract if the owner dies
    * @param days_ number of days from current time that the owner has to check-in prior to, otherwise the kin can claim ownership
    */
    function setDeadmanSwitch(address kin_, uint256 days_) onlyOwner external returns (bool){
      // require(days_ < 365, "QMSI-ERC721: Must check-in once a year");
      if(days_ > 365){
        revert InvalidRange(days_);
      }
      // require(kin_ != address(0), CANNOT_TRANSFER_TO_ZERO_ADDRESS);
      if(kin_ == address(0)){
        revert Unauthorized(kin_);
      }
      _kin = kin_;
      _timestamp = block.timestamp + (days_ * 1 days);
      emit SetDeadSwitch(kin_, days_);
      return true;
    }
    /**
    * @notice to be used by the next of kin to claim ownership of the smart contract if the time has expired
    * @return true on successful owner transfer
    */
    function claimSwitch() external returns (bool){
      // require(msg.sender == _kin, "QMSI-ERC721: Only next of kin can claim a deadman's switch");
      if(msg.sender != _kin){
        revert Unauthorized(_kin);
      }
      // require(block.timestamp > _timestamp, "QMSI-ERC721: Deadman is alive");
      if(block.timestamp < _timestamp){
        revert InvalidRange(block.timestamp);
      }

      emit OwnershipTransferred(owner, _kin);
      owner = _kin;
      return true;
    }
}
