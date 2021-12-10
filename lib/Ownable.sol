// SPDX-License-Identifier: MIT
pragma solidity  = 0.8.9;
import "./Context.sol";
abstract contract Ownable is Context {
    address private _owner;
    address public pendingOwner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TransferPendingOwner(address indexed previousOwner, address indexed newOwner);
    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    // constructor() {
    //     _owner = msg.sender;
    //     emit OwnershipTransferred(address(0), msg.sender);
    // }

    function ownerInit(address _initializeOwner) internal {
        _owner = _initializeOwner;
        emit OwnershipTransferred(address(0), _initializeOwner);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Modifier throws if called by any account other than the pendingOwner.
     */
    modifier onlyPendingOwner() {
        require(msg.sender == pendingOwner, "no permission");
        _;
    }

    /**
     * @dev Allows the current owner to set the pendingOwner address.
     * @param newOwner The address to transfer ownership to.
     */
    //转移owner权限函数
    function transferOwnership(address newOwner)  public onlyOwner {
        pendingOwner = newOwner;//设置pendingOwner为newOwner
        emit TransferPendingOwner(msg.sender, pendingOwner);
    }

    /**
     * @dev Allows the pendingOwner address to finalize the transfer.
     */
    //接受owner权限函数，仅pendingOwner可调用
    function acceptOwnership()  public onlyPendingOwner {
        emit OwnershipTransferred(_owner, pendingOwner);
        _owner = pendingOwner;//更新owner为pendingOwner
        pendingOwner = address(0);//pendingOwner置为零地址
    }

}