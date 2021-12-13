// SPDX-License-Identifier: MIT
pragma solidity  = 0.8.9;
import "./Ownable.sol";
contract BlockedList is Ownable {
    mapping(address => bool) internal blockList;
    address public configurationController;
    event AddBlockList(address _account);
    event RemoveBlockList(address _account);
    event SetConfigAdmin(address _owner, address _account);
    constructor(address _configurationController){
        configurationController = _configurationController;
    }
    function isBlocked(address _account) public view  returns(bool) {
        return blockList[_account];
    }
    modifier onlyConfigurationController() {
        require(msg.sender== configurationController, "caller is not the admin");
        _;
    }

    function setConfigurationController(address _configurationController) public onlyOwner{
        require(_configurationController != address(0), "the account is zero address");
        emit SetConfigAdmin(configurationController, _configurationController);
        configurationController = _configurationController;

    }

    function addBlockList(address[] memory _accountList) public onlyConfigurationController {
        uint256 length = _accountList.length;
        for (uint i = 0; i < length; i++) {
            blockList[_accountList[i]] = true;
            emit AddBlockList(_accountList[i]);
        }
    }

    function removeBlockList(address[] memory _accountList) public onlyConfigurationController{
        uint256 length = _accountList.length;
        for (uint i = 0; i < length; i++) {
            blockList[_accountList[i]] = true;
            emit RemoveBlockList(_accountList[i]);
        }
    }
}