//SPDX-License-Identifier: MIT
pragma solidity  = 0.8.9;
import "./Ownable.sol";

/// @title MemberMgr - add, delete, suspend and resume merchant.
contract MemberMgr is Ownable {
    address public custodian;
    address private repository;
    enum MerchantStatus {STOPPED, VALID}
    struct MerchantStatusData {
        MerchantStatus status;
        bool _exist;
    }

    struct MerchantList {
        address[] list;
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
    mapping(uint256 => MerchantList) internal merchantList;

    function getRepository() external view returns (address) {
        return repository;
    }

    function getMerchantNumber(uint256 chainid) public view returns (uint){
        return merchantList[chainid].list.length;
    }

    function getMerchantList(uint256 chainid) public view returns (address[] memory) {
        return merchantList[chainid].list;
    }

    function getMerchantState(uint chainid, uint index) public view returns (address _addr, string memory _status){
        require(index < merchantList[chainid].list.length, "invalid index");
        address addr = merchantList[chainid].list[index];
        MerchantStatusData memory data = merchantStatus[addr][chainid];
        _addr = addr;
        _status = getStatusString(data);
    }

    modifier onlyCustodian() {
        require(msg.sender == custodian, "not custodian");
        _;
    }

    event CustodianSet(address indexed custodian);

    function setCustodian(address _custodian) external onlyOwner returns (bool) {
        require(_custodian != address(0), "invalid custodian address");
        custodian = _custodian;
        emit CustodianSet(_custodian);
        return true;
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

        merchantList[chainid].list.push(merchant);
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

    function setRepository(address _repository) public onlyCustodian returns (bool) {
        require(_repository != address(0), "invalid repository address");
        repository = _repository;
        emit RepositorySet(repository);
        return true;
    }
}
