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
    function bridgeMint(address to, uint256 amount) external returns (bool);
}

interface MemberMgr{
    function repository() external view returns(address);
    function isMerchant(uint chainid, address addr) external view returns (bool);
}

contract Bridge is Ownable{
    using SafeERC20 for IERC20;

    struct PairInfo{
        bool pauseStatus;   // Whether the pair has been disabled.
        bool bindingStatus; // Whether the pair has been supported.
        uint256 minAmount;  // Minimum amount to request transaction
    }

    struct CctokenConfig {
        bool isCcToken;
        address  controllerAddr;
    }

    struct ExchangeInfo{
        address _tokenA;    // The token that request to cross-chain.
        address _tokenB;    // The token runs on the target chain.
        uint256 _chainIDB;  // Target chain.
        uint256 _amount;    // Amount of tokenA.
        bytes32 _r;         // Signature r.
        bytes32 _s;         // Signature s.
        uint8 _v;           // Signature v.
        uint256 _deadline;  // Expiration time.
        uint256 _fee;       // Amount of transaction fee.
        bytes16 _challenge; // mask.
    }

    struct ConfirmInfo{
        address _tokenA;    // The token that request to cross-chain.
        address _tokenB;    // The token runs on the target chain.
        uint256 _chainIDA;  // The chain that tokenA runs on.
        uint256 _amount;    // Amount of tokenA.
        address _to;        // Destination address for the tokenB
        uint256 _fee;
        uint256 _orderID;   // Order id.
    }

    uint256 public ID;                      // Cumulative order quantity.
    address public memberMgr;               // Manager contract of Merchant and repository.
    address public feeTo;                   // Deposit address of transaction fee.
    address public relayer;                 // Address of the relayer.
    address public WETH;
    address public configurationController; // Configuration management address of the bridge.
    bool internal isInitialized;
    
    mapping(address => mapping(uint256 => mapping(address => PairInfo))) public pairs;
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

    event Confirm(
        uint256 indexed _orderID,
        address indexed _sourceAccount,
        address _tokenA,
        address _tokenB,
        uint256 _chainIDA,
        uint256 _amount,
        address _to,
        uint256 _fee
    );
    
    /// @notice An event emitted when a "memberMgr" address changes.
    event MemberMgrReset(address _before, address _current);

    /// @notice An event emitted when a "relayer" address changes.
    event RelayerReset(address _before, address _current);

    /// @notice An event emitted when a "feeTo" address changes.
    event FeeToReset(address _before, address _current);

    /// @notice An event emitted when a "configurationController" address changes.
    event SetConfigAdmin(address _owner, address _account);

    /// @notice An event emitted when a "pairs" sets.
    event SetPair(address _tokenA, uint256 _chainID, address _tokenB, bool _pauseStatus, bool _bindingStatus, uint256 _minAmount);
    
    /// @notice An event emitted when a "CcToken" changes its status.
    event SetCcToken(address _cctoken, bool _status);
    
    /// @notice An event emitted when the contract initializes its public variables.
    event Initialize(address _owner, address _memberMgr, address _relayer, address _configurationController, address _feeTo, address _WETH);
    
    /// @notice An event emitted when a "CcToken" changes its controller.
    event SetControllerAddr(address _cctoken, address _controller);


    modifier onlyConfigurationController() {
        require(msg.sender== configurationController, "No permission");
        _;
    }

    /**
     * @dev Initialization function, can only be used once to initialize the necessary configuration info when deploy the proxy contract.
     */
    function initialize(address _owner, address _memberMgr, address _relayer, address _configurationController, address _feeTo, address _WETH) external {
        require(!isInitialized, "Initialized");
        require(memberMgr != address(0), "memberMgr: address 0");
        require(_relayer != address(0), "relayer: address 0");
        require(_WETH != address(0), "WETH: address 0");
        ownerInit(_owner);
        memberMgr = _memberMgr;
        relayer = _relayer;
        configurationController = _configurationController;
        feeTo = _feeTo;
        WETH = _WETH;
        isInitialized = true;
        emit Initialize(_owner, _memberMgr, _relayer, _configurationController, _feeTo, _WETH);
    }


    function setPair(address _tokenA, uint256 _chainID, address _tokenB, bool _pauseStatus, 
    bool _bindingStatus, uint256 _minAmount) external onlyConfigurationController{
        PairInfo storage pair = pairs[_tokenA][_chainID][_tokenB];
        pair.pauseStatus = _pauseStatus;
        pair.bindingStatus = _bindingStatus;
        pair.minAmount = _minAmount;
        emit SetPair(_tokenA, _chainID, _tokenB, _pauseStatus, _bindingStatus, _minAmount);
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

    function setRelayer(address _relayer) external onlyConfigurationController {
        require(_relayer != address(0), "relayer: address 0");
        require(relayer != _relayer);
        emit RelayerReset(relayer , _relayer);
        relayer = _relayer;
    }

    function setFeeTo(address _feeTo) external onlyConfigurationController {
        require(_feeTo != address(0), "feeTo: address 0");
        require(feeTo != _feeTo, "Repeat setting");
        emit FeeToReset(feeTo, _feeTo);
        feeTo = _feeTo;
    }

    function setMemberMgr(address _memberMgr) external onlyOwner {
        require(_memberMgr != address(0), "repository: address 0");
        require(memberMgr != _memberMgr, "Repeat setting");
        emit MemberMgrReset(memberMgr , _memberMgr);
        memberMgr = _memberMgr;
    }

    /**
     * @dev Set the controller of the bridge, only the owner has the permission.
     */
    function setConfigurationController(address _configurationController) external onlyOwner{
        require(_configurationController != address(0), "controller: address 0");
        emit SetConfigAdmin(configurationController, _configurationController);
        configurationController = _configurationController;

    }

    /**
     * @dev Internal function, get the chainID.
     */
    function getChainId() internal view returns(uint256){
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    /**
     * @dev Internal function, verify the signature.
     */
    function checkFee(ExchangeInfo memory info) view internal {
        bytes  memory salt=abi.encodePacked(info._tokenA, info._tokenB, getChainId(), info._chainIDB, info._amount, info._deadline, info._fee, info._challenge);
        bytes  memory Message=abi.encodePacked(
                    "\x19Ethereum Signed Message:\n",
                    "216",
                    salt
                );
        bytes32 digest = keccak256(Message);
        address signer=ecrecover(digest, info._v, info._r, info._s);
        require(signer != address(0), "signer: address 0");
        require(signer == relayer, "invalid signature");
    }

    /**
     * @dev Users can initiate cross-chain requests. And the relayer is required 
     * to sign the transaction fee of the order.
     */
    function exchange(ExchangeInfo memory info) public payable returns(bool){
        require(MemberMgr(memberMgr).isMerchant(info._chainIDB, msg.sender), "invalid merchant");
        require(info._amount >= info._fee, "the amount less than transaction fee");
        require(info._deadline >= block.timestamp, "expired fee");
        PairInfo memory pair = pairs[info._tokenA][info._chainIDB][info._tokenB];
        require(!pair.pauseStatus, "the pair is disable");
        require(pair.bindingStatus, "invalid pair");
        require(info._amount >= pair.minAmount, "Less than the minimum amount");

        checkFee(info);
        uint256 _orderID = getChainId() << 240 | info._chainIDB << 224 | uint256(ID) << 160;
        ID++;
        uint256 amount0 = info._amount - info._fee;
        /**
         * Different processing methods according to the three types of `_tokenA`.
         * 1. ccToken (burn)
         * 2. eth (exchange into WETH and transfer to repository)
         * 3. standard tokens issued by third parties (transfer to repository)
         */
        if (ccTokenInfo[info._tokenA].isCcToken){ 
            IERC20(info._tokenA).safeTransferFrom(msg.sender, address(this), amount0);
            IERC20(info._tokenA).safeTransferFrom(msg.sender, feeTo, info._fee);
            IERC20(info._tokenA).burn(amount0);
            emit Exchange(_orderID, msg.sender, info._tokenA, info._tokenB, getChainId(), info._chainIDB, info._amount, info._deadline, info._fee);
            return true;
        }
        address repository = MemberMgr(memberMgr).repository();
        require(repository != address(0), "invalid repository");

        if (info._tokenA == address(0)){
            require(msg.value == info._amount, "invalid amount");
            uint256 ethAmount = msg.value;
            IWETH(WETH).deposit{value:ethAmount}();
            IERC20(WETH).safeTransfer(repository, ethAmount - info._fee);
            IERC20(WETH).safeTransfer(feeTo, info._fee);
            emit Exchange(_orderID, msg.sender, info._tokenA, info._tokenB, getChainId(), info._chainIDB, ethAmount, info._deadline, info._fee);
            return true;
        }
        IERC20(info._tokenA).safeTransferFrom(msg.sender, repository, amount0);
        IERC20(info._tokenA).safeTransferFrom(msg.sender, feeTo, info._fee);
        emit Exchange(_orderID, msg.sender, info._tokenA, info._tokenB, getChainId(), info._chainIDB, info._amount, info._deadline, info._fee);
        return true;
    }

    /**
     * @dev After relayer confirms the user's cross-chain request, 
     * the bridge controller will call this function to mint/transfer tokenB to the destination address on the target chain.
     */
    function confirm(ConfirmInfo memory info) external onlyConfigurationController returns(bool){
        // Check the information of exchange, including transaction fee, amount, pairinfo etc.
        PairInfo memory pair = pairs[info._tokenB][info._chainIDA][info._tokenA];
        require(MemberMgr(memberMgr).isMerchant(info._chainIDA, info._to), "invalid merchant");
        require(!orderIDStatus[info._orderID], "the orderID already finished");
        require(info._amount >= info._fee, "the amount less than transaction fee");
        uint256 amount0 =  info._amount - info._fee;
        require(!pair.pauseStatus, "the pair is in pause");
        require(pair.bindingStatus, "invalid pair");
        require(info._amount >= pair.minAmount, "Less than the minimum amount");
        orderIDStatus[info._orderID] = true;
        /**
         * Different processing methods according to the three types of `_tokenB` (target token).
         * 1. ccToken
         * 2. eth
         * 3. standard tokens issued by third parties
         */
        if (ccTokenInfo[info._tokenB].isCcToken) {
            address controller = ccTokenInfo[info._tokenB].controllerAddr;
            require(Controller(controller).bridgeMint(info._to, amount0), "mint failed");
            emit Confirm(info._orderID, msg.sender, info._tokenA, info._tokenB, info._chainIDA, info._amount, info._to, info._fee);
            return true;
        }
        address repository = MemberMgr(memberMgr).repository();
        require(repository != address(0), "invalid repository");

        if(info._tokenB == address(0)){
            IERC20(WETH).safeTransferFrom(repository, address(this), amount0);
            IWETH(WETH).withdraw(amount0);
            payable(info._to).transfer(amount0);
            emit Confirm(info._orderID, msg.sender, info._tokenA, info._tokenB, info._chainIDA, info._amount, info._to, info._fee);
            return true;
        }
        IERC20(info._tokenB).safeTransferFrom(repository, info._to, amount0);
        emit Confirm(info._orderID, msg.sender, info._tokenA, info._tokenB, info._chainIDA, info._amount, info._to, info._fee);
        return true;
    }

    /**
     * @dev Used to withdraw tokens that users have deposited by mistake.
     * - Only the owner of the contract has the permission.
     * - `_token` refers to the token contract address.
     */
    function withdrawToken(address _token) external onlyOwner{
        IERC20(_token).safeTransfer(msg.sender, IERC20(_token).balanceOf(address(this)));
    }

    /**
     * @dev Used to withdraw ETH that users have deposited by mistake.
     * - Only the owner of the contract has the permission.
     */
    function withdrawETH() external payable onlyOwner{
        uint256 value = address(this).balance;
        payable(owner()).transfer(value);
    }

    receive() external payable {
        require(msg.sender == WETH, "only weth");
    }

}
