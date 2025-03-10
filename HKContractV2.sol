// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract LottoChainDecentralizedHKPool {
    address public owner;
    address public USDT;
    uint256 public minBet = 1;
    uint256 public maxBet = 99;
    uint256 public ethBetPrice = 0.000175 ether;
    uint256 public usdtBetPrice = 0.5 * 10**6; // 0.5 USDT (USDT 6 decimal)

    struct Bet {
        address player;
        uint256 number;
        uint256 betAmount;
        bool isETH;
    }

    struct Comment {
        address user;
        string text;
        uint256 likes;
    }

    mapping(uint256 => Bet[]) public bets;
    mapping(address => uint256) public ethWinnings;
    mapping(address => uint256) public usdtWinnings;
    mapping(uint256 => uint256) public results;
    mapping(uint256 => Comment[]) public comments;

    event BetPlaced(address indexed player, uint256 number, uint256 betAmount, bool isETH);
    event WinnerSetETH(address indexed winner, uint256 amount);
    event WinnerSetUSDT(address indexed winner, uint256 amount);
    event LotteryResult(uint256 indexed drawId, uint256 number);
    event CommentAdded(uint256 indexed drawId, address user, string text);
    event CommentEdited(uint256 indexed drawId, address user, uint256 commentIndex, string newText);
    event CommentDeleted(uint256 indexed drawId, address user, uint256 commentIndex);
    event LikeAdded(uint256 indexed drawId, address user, uint256 commentIndex);
    event WithdrawETH(address indexed user, uint256 amount);
    event WithdrawUSDT(address indexed user, uint256 amount);
    event ReceivedETH(address indexed sender, uint256 amount);
    event ReceivedUSDT(address indexed sender, uint256 amount);
    event WithdrawETHExec(address indexed owner, uint256 amount);
    event WithdrawUSDTExec(address indexed owner, uint256 amount);

    constructor(address _usdt) {
        owner = msg.sender;
        USDT = _usdt;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    function placeBet(uint256 _number, uint256 _times, bool _isETH) external payable {
        require(_number >= 0 && _number <= 9999, "Invalid number (0 - 9999)");
        require(_times >= minBet && _times <= maxBet, "Bet count out of range");

        uint256 totalCost = _times * (_isETH ? ethBetPrice : usdtBetPrice);
        
        if (_isETH) {
            require(msg.value >= totalCost, "Insufficient ETH sent");
            if (msg.value > totalCost) {
                payable(msg.sender).transfer(msg.value - totalCost);
            }
        } else {
            (bool success, bytes memory returnData) = address(USDT).call(
                abi.encodeWithSelector(IERC20.transferFrom.selector, msg.sender, address(this), totalCost)
            );
            require(success && (returnData.length == 0 || abi.decode(returnData, (bool))), "USDT transfer failed");
        }

        bets[_number].push(Bet(msg.sender, _number, _times, _isETH));
        emit BetPlaced(msg.sender, _number, _times, _isETH);
    }

    function setWinnerETH(uint256 _number, address _winner, uint256 _amount) external onlyOwner {
        ethWinnings[_winner] += _amount;
        emit WinnerSetETH(_winner, _amount);
    }

    function setWinnerUSDT(uint256 _number, address _winner, uint256 _amount) external onlyOwner {
        usdtWinnings[_winner] += _amount;
        emit WinnerSetUSDT(_winner, _amount);
    }

    function claimETH() external {
        uint256 amount = ethWinnings[msg.sender];
        require(amount > 0, "No ETH winnings");
    
        ethWinnings[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH transfer failed");

        emit WithdrawETH(msg.sender, amount);
    }

    function claimUSDT() external {
        uint256 amount = usdtWinnings[msg.sender];
        require(amount > 0, "No USDT winnings");
        usdtWinnings[msg.sender] = 0;
        
        require(IERC20(USDT).transfer(msg.sender, amount), "USDT transfer failed");
        emit WithdrawUSDT(msg.sender, amount);
    }

    function setLotteryResult(uint256 _drawId, uint256 _number) external onlyOwner {
        results[_drawId] = _number;
        emit LotteryResult(_drawId, _number);
    }

    function addComment(uint256 _drawId, string memory _text) external {
        comments[_drawId].push(Comment(msg.sender, _text, 0));
        emit CommentAdded(_drawId, msg.sender, _text);
    }

    function editComment(uint256 _drawId, uint256 _commentIndex, string memory _newText) external {
        require(comments[_drawId][_commentIndex].user == msg.sender, "Not your comment");
        comments[_drawId][_commentIndex].text = _newText;
        emit CommentEdited(_drawId, msg.sender, _commentIndex, _newText);
    }

    function deleteComment(uint256 _drawId, uint256 _commentIndex) external {
        require(comments[_drawId][_commentIndex].user == msg.sender, "Not your comment");
        
        uint256 lastIndex = comments[_drawId].length - 1;
        if (_commentIndex != lastIndex) {
            comments[_drawId][_commentIndex] = comments[_drawId][lastIndex];
        }
        comments[_drawId].pop();

        emit CommentDeleted(_drawId, msg.sender, _commentIndex);
    }

    function contractUSDTBalance() external view returns (uint256) {
        return IERC20(USDT).balanceOf(address(this));
    }

    function contractETHBalance() external view returns (uint256) {
       return address(this).balance;
    }

    function WithdrawETHExec(uint256 _amount) external onlyOwner {
        require(address(this).balance >= _amount, "Insufficient ETH balance");
        (bool success, ) = payable(owner).call{value: _amount}("");
        require(success, "ETH withdrawal failed");
        emit WithdrawETHExec(owner, _amount);
    }

    function WithdrawUSDTExec(uint256 _amount) external onlyOwner {
        uint256 balance = IERC20(USDT).balanceOf(address(this));
        require(_amount <= balance, "Insufficient USDT balance");
        
        require(IERC20(USDT).transfer(owner, _amount), "USDT transfer failed");
        emit WithdrawUSDTExec(owner, _amount);
    }

    function depositUSDT(uint256 _amount) external {
        require(IERC20(USDT).transferFrom(msg.sender, address(this), _amount), "USDT deposit failed");
        emit ReceivedUSDT(msg.sender, _amount);
    }

    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }

    fallback() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }
}
