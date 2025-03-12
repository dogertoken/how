// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract LottoChainDecentralizedHKPool {
    struct Bet {
        address player;
        uint256 number;
        uint256 betAmount;
    }

    address public owner;
    uint256 public minBet = 1;
    uint256 public maxBet = 99;
    uint256 public ethBetPrice = 0.000175 ether;
    bool public bettingOpen = true;
    
    mapping(uint256 => Bet[]) public bets;
    mapping(address => uint256) public winnings;
    mapping(uint256 => uint256) public results;

    event BetPlaced(address indexed player, uint256 number, uint256 betAmount);
    event WinnerSet(address indexed winner, uint256 amount);
    event LotteryResult(uint256 indexed drawId, uint256 number);
    event Withdraw(address indexed user, uint256 amount);
    event ReceivedETH(address indexed sender, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier whenBettingOpen() {
        require(bettingOpen, "Betting is closed");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function placeBet(uint256 _number, uint256 _times) external payable whenBettingOpen {
        require(_number <= 9999, "Invalid number (0 - 9999)");
        require(_times >= minBet && _times <= maxBet, "Bet count out of range");

        uint256 totalCost = _times * ethBetPrice;
        require(msg.value == totalCost, "Incorrect ETH amount");

        bets[_number].push(Bet(msg.sender, _number, _times));
        emit BetPlaced(msg.sender, _number, _times);
    }

    function closeBetting() external onlyOwner {
        bettingOpen = false;
    }

    function setWinner(uint256 _number, address _winner, uint256 _amount) external onlyOwner {
        winnings[_winner] += _amount;
        emit WinnerSet(_winner, _amount);
    }

    function claimWinnings() external {
        uint256 amount = winnings[msg.sender];
        require(amount > 0, "No winnings available");
        
        winnings[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH transfer failed");

        emit Withdraw(msg.sender, amount);
    }

    function setLotteryResult(uint256 _drawId, uint256 _number) external onlyOwner {
        results[_drawId] = _number;
        emit LotteryResult(_drawId, _number);
    }

    function contractETHBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function withdrawETH(uint256 _amount) external onlyOwner {
        require(address(this).balance >= _amount, "Insufficient ETH balance");
        (bool success, ) = payable(owner).call{value: _amount}("");
        require(success, "ETH withdrawal failed");
    }

    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }
}
