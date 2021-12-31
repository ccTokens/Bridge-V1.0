//SPDX-License-Identifier: MIT
pragma solidity  = 0.8.9;
import "./Ownable.sol";

/// @title MemberMgr - add, delete, suspend and resume merchant.
contract MemberMgr is Ownable {
    address public repository;
    enum MerchantStatus {STOPPED, VALID}
    struct MerchantStatusData {
        MerchantStatus status;
        bool _exist;
    }

    struct MerchantList {
        address[] merchantList;
    }

    function getStatusString(MerchantStatusData memory data) internal pure returns (string memory) {
        if (!data._exist) return "not-exist";
        if (data.status == MerchantStatus.STOPPED) {
            return "stopped";
        } else if (data.status == MerchantStatus.VALID) {
            return "valid";
        } else {
            return "not-exist";
        }
    }

    mapping(address => mapping(uint256 => MerchantStatusData)) public merchantStatus;
    mapping(uint256 => MerchantList) internal chainMerchantList;

    function getMerchantNumber(uint256 chainid) public view returns (uint){
        return chainMerchantList[chainid].merchantList.length;
    }

    function getMerchantList(uint256 chainid) public view returns (address[] memory) {
        return chainMerchantList[chainid].merchantList;
    }

    function getMerchantState(uint chainid, uint index) public view returns (address _addr, string memory _status){
        require(index < chainMerchantList[chainid].merchantList.length, "invalid index");
        address addr = chainMerchantList[chainid].merchantList[index];
        MerchantStatusData memory data = merchantStatus[addr][chainid];
        _addr = addr;
        _status = getStatusString(data);
    }

    event NewMerchant(address indexed merchant);

    function addMerchant(uint chainid, address merchant) external onlyOwner returns (bool) {
        require(merchant != address(0), "invalid merchant address");
        MerchantStatusData memory data = merchantStatus[merchant][chainid];
        require(!data._exist, "merchant exists");
        merchantStatus[merchant][chainid] = MerchantStatusData({
            status : MerchantStatus.VALID,
            _exist : true
            });

        chainMerchantList[chainid].merchantList.push(merchant);
        emit NewMerchant(merchant);
        return true;
    }

    event MerchantStopped(address indexed merchant);

    function stopMerchant(uint chainid, address merchant) external onlyOwner returns (bool) {
        require(merchant != address(0), "invalid merchant address");
        MerchantStatusData memory data = merchantStatus[merchant][chainid];
        require(data._exist, "merchant not exists");
        require(data.status == MerchantStatus.VALID, "invalid status");
        merchantStatus[merchant][chainid].status = MerchantStatus.STOPPED;

        emit MerchantStopped(merchant);
        return true;
    }

    event MerchantResumed(address indexed merchant);

    function resumeMerchant(uint chainid, address merchant) external onlyOwner returns (bool) {
        require(merchant != address(0), "invalid merchant address");
        MerchantStatusData memory data = merchantStatus[merchant][chainid];
        require(data._exist, "merchant not exists");
        require(data.status == MerchantStatus.STOPPED, "invalid status");
        merchantStatus[merchant][chainid].status = MerchantStatus.VALID;

        emit MerchantResumed(merchant);
        return true;
    }

    function isMerchant(uint chainid, address addr) external view returns (bool) {
        return merchantStatus[addr][chainid]._exist && merchantStatus[addr][chainid].status == MerchantStatus.VALID;
    }
    
    event RepositorySet(address indexed repository);

    function setRepository(address _repository) public onlyOwner returns (bool) {
        require(_repository != address(0), "invalid repository address");
        repository = _repository;

        emit RepositorySet(repository);
        return true;
    }
}
