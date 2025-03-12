// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LottoChainDecentralizedHKPool {
    address public owner;
    IERC20 public USDT;
    uint256 public minBet = 1;
    uint256 public maxBet = 99;
    uint256 public ethBetPrice = 0.000175 ether;
    uint256 public usdtBetPrice = 0.5 * 10**6; // 0.5 USDT (6 desimal)

    struct Bet {
        address player;
        uint256 number;
        uint256 betAmount;
        bool isETH;
    }

    mapping(uint256 => Bet[]) public bets;
    mapping(address => uint256) public ethWinnings;
    mapping(address => uint256) public usdtWinnings;
    mapping(uint256 => uint256) public results;
    
    event BetPlaced(address indexed player, uint256 number, uint256 betAmount, bool isETH);
    event WinnerSet(address indexed winner, uint256 amount, bool isETH);
    event LotteryResult(uint256 indexed drawId, uint256 number);
    event Withdraw(address indexed user, uint256 amount, bool isETH);
    event DepositUSDT(address indexed sender, uint256 amount);
    event ReceivedETH(address indexed sender, uint256 amount);

    constructor(address _usdt) {
        owner = msg.sender;
        USDT = IERC20(_usdt);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    function placeBet(uint256 _number, uint256 _times, bool _isETH) external payable {
        require(_number <= 9999, "Invalid number (0 - 9999)");
        require(_times >= minBet && _times <= maxBet, "Bet count out of range");

        uint256 totalCost = _times * (_isETH ? ethBetPrice : usdtBetPrice);
        
        if (_isETH) {
            require(msg.value == totalCost, "Incorrect ETH amount");
        } else {
            require(USDT.transferFrom(msg.sender, address(this), totalCost), "USDT transfer failed");
        }

        bets[_number].push(Bet(msg.sender, _number, _times, _isETH));
        emit BetPlaced(msg.sender, _number, _times, _isETH);
    }

    function setWinner(uint256 _number, address _winner, uint256 _amount, bool _isETH) external onlyOwner {
        if (_isETH) {
            ethWinnings[_winner] += _amount;
        } else {
            usdtWinnings[_winner] += _amount;
        }
        emit WinnerSet(_winner, _amount, _isETH);
    }

    function claimWinnings(bool _isETH) external {
        uint256 amount = _isETH ? ethWinnings[msg.sender] : usdtWinnings[msg.sender];
        require(amount > 0, "No winnings available");
        
        if (_isETH) {
            ethWinnings[msg.sender] = 0;
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            usdtWinnings[msg.sender] = 0;
            require(USDT.transfer(msg.sender, amount), "USDT transfer failed");
        }
        emit Withdraw(msg.sender, amount, _isETH);
    }

    function setLotteryResult(uint256 _drawId, uint256 _number) external onlyOwner {
        results[_drawId] = _number;
        emit LotteryResult(_drawId, _number);
    }

    function contractUSDTBalance() external view returns (uint256) {
        return USDT.balanceOf(address(this));
    }

    function contractETHBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function withdrawETH(uint256 _amount) external onlyOwner {
        require(address(this).balance >= _amount, "Insufficient ETH balance");
        (bool success, ) = payable(owner).call{value: _amount}("");
        require(success, "ETH withdrawal failed");
    }

    function withdrawUSDT(uint256 _amount) external onlyOwner {
        require(USDT.balanceOf(address(this)) >= _amount, "Insufficient USDT balance");
        require(USDT.transfer(owner, _amount), "USDT transfer failed");
    }

    function depositUSDT(uint256 _amount) external {
        require(USDT.transferFrom(msg.sender, address(this), _amount), "USDT deposit failed");
        emit DepositUSDT(msg.sender, _amount);
    }

    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }
}
