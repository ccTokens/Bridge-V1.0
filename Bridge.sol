// SPDX-License-Identifier: MIT
pragma solidity  = 0.8.9;
import "./lib/Ownable.sol";
import "./lib/SafeERC20.sol";
interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

interface Controller {
    function bridgeMint(address to, uint256 amount) external  returns (bool);
}

interface BlockedList{
    function isBlockedList(address _account) external view  returns(bool);
}

contract Bridge is Ownable{
    using SafeERC20 for IERC20;

    struct PairInfo{
        bool pauseStatus;
        bool bindingStatus;
        uint256 minAmount;
    }

    struct CctokenConfig {
        bool isCcToken;
        address  controllerAddr;
    }

    struct ExchangeInfo{
        address _tokenA;
        address _tokenB;
        uint256 _chainIDB;
        uint256 _amount;
        bytes32 _r;
        bytes32 _s;
        uint8 _v;
        uint256 _deadline;
        uint256 _fee;
        bytes16 _challenge;
    }

    struct TransferAndMintInfo{
        address _tokenA;
        address _tokenB;
        uint256 _chainIDA;
        uint256 _amount;
        address _to;
        uint256 _fee;
        uint256 _orderID;
    }

    uint256 public ID;
    address public feeWallet;
    address public storehouse;
    address public signatoryAddress;
    address public WETH;
    address public configurationController;
    BlockedList public blockedList;
    bool internal isInitialized;
    mapping(address => mapping(uint256 => mapping(address => PairInfo))) public pairBinding;
    mapping(uint256 => bool) public orderIDStatus;
    mapping(address => CctokenConfig) public ccTokenInfo;
    
    

    event Exchange(
        uint256 indexed _orderID,
        address indexed _sourceAccount,
        address _tokenA,
        address _tokenB,
        uint256 _chainIDA,
        uint256 _chainIDB,
        uint256 _amount,
        uint256 _deadline,
        uint256 _fee
    );

    event TransferAndMint(
        uint256 indexed _orderID,
        address indexed _sourceAccount,
        address _tokenA,
        address _tokenB,
        uint256 _chainIDA,
        uint256 _amount,
        address _to,
        uint256 _fee
    );

    event StoreHouseReset(address _before, address _current);
    event BlockListReset(address _before, address _current);
    event SignatoryAddrReset(address _before, address _current);

    event SetConfigAdmin(address _owner, address _account);
    event SetBindingToken(address _tokenA, uint256 _chainID, address _tokenB, bool _pauseStatus, bool _bindingStatus, uint256 _minAmount);
    event SetCcToken(address _cctoken, bool _status);
    event Initialize(address _owner, address _storehouse, address _signatoryAddress, address _configurationController, address _feeWallet, address _WETH,address _blockedList);
    event SetControllerAddr(address _cctoken, address _controller);
    // constructor(address _storehouse, address _WETH, address _signatoryAddress, address _configurationController, BlockedList _blockedList) {
    //     initialize(_storehouse, _signatoryAddress, _WETH, _blockedList);
    //     configurationController = _configurationController;
    // }

    modifier onlyConfigurationController() {
        require(msg.sender== configurationController, "caller is not the admin");
        _;
    }


    function setBindingToken(address _tokenA, uint256 _chainID, address _tokenB, bool _pauseStatus, 
    bool _bindingStatus, uint256 _minAmount) external onlyConfigurationController{
        PairInfo storage pair = pairBinding[_tokenA][_chainID][_tokenB];
        pair.pauseStatus = _pauseStatus;
        pair.bindingStatus = _bindingStatus;
        pair.minAmount = _minAmount;
        emit SetBindingToken(_tokenA, _chainID, _tokenB, _pauseStatus, _bindingStatus, _minAmount);
    }

    function setCcToken(address _cctoken, bool _status) external onlyConfigurationController{
        ccTokenInfo[_cctoken].isCcToken = _status;
        emit SetCcToken(_cctoken, _status);
    }

    function setControllerAddr(address _cctoken, address _controller) external onlyConfigurationController{
        ccTokenInfo[_cctoken].controllerAddr = _controller;
        emit SetControllerAddr(_cctoken, _controller);
    }

    function setCctokenConfig(address _cctoken, bool _status, address _controller) external onlyConfigurationController {
        ccTokenInfo[_cctoken].isCcToken = _status;
        ccTokenInfo[_cctoken].controllerAddr = _controller;
        emit SetCcToken(_cctoken, _status);
        emit SetControllerAddr(_cctoken, _controller);
    }

    function initialize(address _owner, address _storehouse, address _signatoryAddress, address _configurationController, address _feeWallet, address _WETH, BlockedList _blockedList) external {
        require(!isInitialized, "Can only be initialized once");
        require(_storehouse != address(0), "the storehouse is zero address");
        require(_signatoryAddress != address(0), "the signatoryAddress is zero address");
        require(_WETH != address(0), "the WETH is zero address");
        require(address(_blockedList) != address(0), "the blacklist address is zero address");
        ownerInit(_owner);
        storehouse = _storehouse;
        signatoryAddress = _signatoryAddress;
        configurationController = _configurationController;
        feeWallet = _feeWallet;
        WETH = _WETH;
        blockedList = _blockedList;
        isInitialized = true;
        emit Initialize(_owner, _storehouse, _signatoryAddress, _configurationController, _feeWallet, _WETH, address(_blockedList));
    }

    function setSignatoryAddr(address _signer) external onlyConfigurationController {
        require(_signer != address(0), "the signer is zero address");
        require(signatoryAddress != _signer);
        emit SignatoryAddrReset(signatoryAddress , _signer);
        signatoryAddress = _signer;
    }

    function setBlockList(BlockedList _blockedList) external onlyConfigurationController {
        require(address(_blockedList) != address(0), "the storehouse is zero address");
        require(blockedList != _blockedList, "Repeat setting");
        emit BlockListReset(address(blockedList), address(_blockedList));
        blockedList = _blockedList;
    }

    function setStorehouse(address _storehouse) external onlyConfigurationController {
        require(_storehouse != address(0), "the storehouse is zero address");
        require(storehouse != _storehouse);
        emit StoreHouseReset(storehouse , _storehouse);
        storehouse = _storehouse;
    }

    function setConfigurationController(address _configurationController) external onlyOwner{
        require(_configurationController != address(0), "the account is zero address");
        emit SetConfigAdmin(configurationController, _configurationController);
        configurationController = _configurationController;

    }


    function getChainId() internal view returns(uint256){
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    function checkFee(ExchangeInfo memory info) view internal {
        bytes  memory salt=abi.encodePacked(info._tokenA, info._tokenB, getChainId(), info._chainIDB, info._amount, info._deadline, info._fee, info._challenge);
        bytes  memory Message=abi.encodePacked(
                    "\x19Ethereum Signed Message:\n",
                    "216",
                    salt
                );
        bytes32 digest = keccak256(Message);
        address signer=ecrecover(digest, info._v, info._r, info._s);
        require(signer != address(0), "0 address");
        require(signer == signatoryAddress, "invalid signature");
    }
    
    function exchange(ExchangeInfo memory info) public payable returns(bool){
        require(!blockedList.isBlockedList(msg.sender), "the caller is blacklist address");
        require(info._amount >= info._fee, "the amount less than fee");
        require(info._deadline >= block.timestamp, "expired fee");
        PairInfo memory pair = pairBinding[info._tokenA][info._chainIDB][info._tokenB];
        require(!pair.pauseStatus, "the pair is in pause");
        require(pair.bindingStatus, "invalid pair");
        require(info._amount >= pair.minAmount, "Below the minimum amount limit");

        checkFee(info);
        uint256 _orderID = getChainId() << 240 | info._chainIDB << 224 | uint256(ID) << 160;
        ID++;
        uint256 realAmount = info._amount - info._fee;
        if (ccTokenInfo[info._tokenA].isCcToken){ 
            IERC20(info._tokenA).safeTransferFrom(msg.sender, address(this), realAmount);
            IERC20(info._tokenA).safeTransferFrom(msg.sender, feeWallet, info._fee);
            IERC20(info._tokenA).burn(realAmount);
            emit Exchange(_orderID, msg.sender, info._tokenA, info._tokenB, getChainId(), info._chainIDB, info._amount, info._deadline, info._fee);
            return true;
        }

        if (info._tokenA == address(0)){
            require(msg.value == info._amount, "invalid amount");
            uint256 ethAmount = msg.value;
            IWETH(WETH).deposit{value:ethAmount}();
            IERC20(WETH).safeTransfer(storehouse, ethAmount - info._fee);
            IERC20(WETH).safeTransfer(feeWallet, info._fee);
            emit Exchange(_orderID, msg.sender, info._tokenA, info._tokenB, getChainId(), info._chainIDB, ethAmount, info._deadline, info._fee);
            return true;
        }
        IERC20(info._tokenA).safeTransferFrom(msg.sender, storehouse, realAmount);
        IERC20(info._tokenA).safeTransferFrom(msg.sender, feeWallet, info._fee);
        emit Exchange(_orderID, msg.sender, info._tokenA, info._tokenB, getChainId(), info._chainIDB, info._amount, info._deadline, info._fee);
        return true;
    }

    function transferAndMint(TransferAndMintInfo memory info) external onlyConfigurationController returns(bool){
        PairInfo memory pair = pairBinding[info._tokenB][info._chainIDA][info._tokenA];
        require(!blockedList.isBlockedList(info._to), "the caller or to address is blacklist address");
        require(!orderIDStatus[info._orderID], "the orderID already finished");
        require(info._amount >= info._fee, "the amount less than fee");
        uint256 realAmount =  info._amount - info._fee;
        require(!pair.pauseStatus, "the pair is in pause");
        require(pair.bindingStatus, "invalid pair");
        require(info._amount >= pair.minAmount, "below the minimum amount limit");
        orderIDStatus[info._orderID] = true;
        if (ccTokenInfo[info._tokenB].isCcToken) {
            address controller = ccTokenInfo[info._tokenB].controllerAddr;
            require(Controller(controller).bridgeMint(info._to, realAmount), "mint failed");
            emit TransferAndMint(info._orderID, msg.sender, info._tokenA, info._tokenB, info._chainIDA, info._amount, info._to, info._fee);
            return true;
        }

        if(info._tokenB == address(0)){
            IERC20(WETH).safeTransferFrom(storehouse, address(this), realAmount);
            IWETH(WETH).withdraw(realAmount);
            payable(info._to).transfer(realAmount);
            emit TransferAndMint(info._orderID, msg.sender, info._tokenA, info._tokenB, info._chainIDA, info._amount, info._to, info._fee);
            return true;
        }
        IERC20(info._tokenB).safeTransferFrom(storehouse, info._to, realAmount);
        emit TransferAndMint(info._orderID, msg.sender, info._tokenA, info._tokenB, info._chainIDA, info._amount, info._to, info._fee);
        return true;    
    }

    function withdrawToken(address _token) external onlyOwner{
        IERC20(_token).safeTransfer(msg.sender, IERC20(_token).balanceOf(address(this)));
    }

    function withdrawETH() external payable onlyOwner{
        uint256 value = address(this).balance;
        payable(owner()).transfer(value);
    }

    receive() external payable {
        require(msg.sender == WETH, "only weth");
    }

}