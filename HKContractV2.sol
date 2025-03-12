// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract LottoChainDecentralizedHKPool {
    address public owner;
    uint256 public minBet = 1;
    uint256 public maxBet = 99;
    uint256 public ethBetPrice = 0.000175 ether;

    struct Bet {
        address player;
        uint256 number;
        uint256 betAmount;
        bool isETH;
        uint256 timestamp; // ⏳ Waktu taruhan
    }

    struct Comment {
        address user;
        string text;
        uint256 likes;
    }

    mapping(uint256 => Bet[]) public bets;
    mapping(address => uint256) public ethWinnings;
    mapping(uint256 => uint256) public results;
    mapping(uint256 => uint256) public resultTimestamps; // ⏳ Waktu hasil undian
    mapping(uint256 => Comment[]) public comments;
    mapping(address => Bet[]) public personalBets;
    mapping(uint256 => mapping(address => bool)) public likedComments;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    function placeBet(uint256 _number, uint256 _times, bool _isETH) external payable {
        require(_number >= 0 && _number <= 9999, "Invalid number (0 - 9999)");
        require(_times >= minBet && _times <= maxBet, "Bet count out of range");

        uint256 totalCost = _times * ethBetPrice;
        require(msg.value == totalCost, "Incorrect ETH amount");

        Bet memory newBet = Bet(msg.sender, _number, _times, _isETH, block.timestamp); // ⏳ Simpan waktu
        bets[_number].push(newBet);
        personalBets[msg.sender].push(newBet);
    }

    function setWinnerETH(address _winner, uint256 _amount) external onlyOwner {
        ethWinnings[_winner] += _amount;
    }

    function claimETH() external {
        uint256 amount = ethWinnings[msg.sender];
        require(amount > 0, "No ETH winnings");
    
        ethWinnings[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    function setLotteryResult(uint256 _drawId, uint256 _number) external onlyOwner {
        results[_drawId] = _number;
        resultTimestamps[_drawId] = block.timestamp; // ⏳ Simpan waktu undian
    }

    function addComment(uint256 _drawId, string memory _text) external {
        comments[_drawId].push(Comment(msg.sender, _text, 0));
    }

    function editComment(uint256 _drawId, uint256 _commentIndex, string memory _newText) external {
        require(comments[_drawId][_commentIndex].user == msg.sender, "Not your comment");
        comments[_drawId][_commentIndex].text = _newText;
    }

    function deleteComment(uint256 _drawId, uint256 _commentIndex) external {
        require(comments[_drawId][_commentIndex].user == msg.sender, "Not your comment");
        delete comments[_drawId][_commentIndex];
    }

    function likeComment(uint256 _drawId, uint256 _commentIndex) external {
        require(!likedComments[_drawId][msg.sender], "You already liked this comment");

        comments[_drawId][_commentIndex].likes++;
        likedComments[_drawId][msg.sender] = true;
    }

    function contractETHBalance() external view returns (uint256) {
       return address(this).balance;
    }

    function executeWithdrawETH(uint256 _amount) external onlyOwner {
        require(address(this).balance >= _amount, "Insufficient ETH balance");

        (bool success, ) = payable(owner).call{value: _amount}("");
        require(success, "ETH withdrawal failed");
    }

    function getUserBets(address _user) external view returns (Bet[] memory) {
        return personalBets[_user];
    }

    function getBetHistory(uint256 _drawId) external view returns (Bet[] memory) {
        return bets[_drawId];
    }

    function getDrawTimestamp(uint256 _drawId) external view returns (uint256) {
        return resultTimestamps[_drawId];
    }

    receive() external payable {}
}
