// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract LotDomain {
    struct Domain {
        string name;
        address owner;
        uint256 expiry;
        bool forAuction;
        uint256 minBid;
        bool isRented;
        address renter;
        uint256 rentPaid;
        uint256 rentTarget;
        uint256 reputation;
        string ipfsHash; // Untuk hosting website di IPFS
    }

    uint256 public constant DURATION = 365 days;
    uint256 public nextId = 1;
    address payable public admin;

    mapping(uint256 => Domain) public domains;
    mapping(bytes32 => uint256) private nameToId;
    mapping(bytes32 => address) public nameToAddress;
    mapping(string => mapping(string => address)) public subdomains;
    mapping(uint256 => uint256) public domainStake;
    mapping(uint256 => address) public auctionHighestBidder;
    mapping(uint256 => uint256) public auctionHighestBid;
    mapping(address => address[]) public guardians;
    mapping(string => address[]) public domainTrustees;
    mapping(address => uint256) public pendingReturns;
    mapping(bytes32 => address[]) public domainGuardians;
    mapping(bytes32 => mapping(address => bool)) public guardianApproval;
    mapping(bytes32 => address) public pendingRecovery;
    mapping(bytes32 => address) public nameToAddress;
    mapping(address => bytes32) public addressToName;
    mapping(string => address) public domainOwners;

    event DomainRegistered(string name, address owner, uint256 expiry);
    event DomainRenewed(string name, uint256 newExpiry);
    event DomainTransferred(string name, address from, address to);
    event DomainAuctionStarted(string name, uint256 minBid);
    event DomainBidPlaced(string name, address bidder, uint256 bid);
    event DomainAuctionEnded(string name, address winner, uint256 finalBid);
    event DomainRented(string name, address renter, uint256 paid);
    event RentCompleted(string name, address newOwner);
    event RecoveryRequested(string name, address requester);
    event RecoveryApproved(string name, address newOwner);
    event SubdomainCreated(string mainDomain, string subDomain, address owner);
    event WebsiteUpdated(string name, string ipfsHash);
    event FundsWithdrawn(address admin, uint256 amount);
    event RecoveryInitiated(bytes32 indexed domain, address indexed newOwner);
    event RecoveryApproved(bytes32 indexed domain, address indexed approver);
    event RecoveryCompleted(bytes32 indexed domain, address indexed newOwner);

    modifier onlyOwner(string memory name) {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        require(nameToId[nameHash] != 0, "Domain not registered");
        require(domains[nameToId[nameHash]].owner == msg.sender, "Not domain owner");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    constructor() {
        admin = payable(msg.sender);
    }

    function isDomainRegistered(string memory name) public view returns (bool) {
        return nameToId[keccak256(abi.encodePacked(name))] != 0;
    }

    function getRegistrationFee(string memory name) public pure returns (uint256) {
        uint256 length = bytes(name).length;
        require(length >= 1, "Domain name too short");

        if (length == 1) return 0.05 ether;
        if (length == 2) return 0.02 ether;
        if (length == 3) return 0.01 ether;
        if (length >= 4 && length <= 5) return 0.0015 ether;
        if (length >= 6 && length <= 7) return 0.001 ether;
        if (length >= 8 && length <= 10) return 0.0008 ether;
        return 0.0005 ether;
    }

    function registerDomain(string memory name, string memory extension, uint256 rentTarget) public payable {
        string memory fullDomain = string(abi.encodePacked(name, ".lol", extension));
        bytes32 nameHash = keccak256(abi.encodePacked(fullDomain));

        require(nameToId[nameHash] == 0, "Domain already taken"); // Cek apakah sudah terdaftar
        uint256 requiredFee = getRegistrationFee(name);
        require(msg.value >= requiredFee, "Insufficient registration fee");

        uint256 tokenId = nextId++;
        domains[tokenId] = Domain(fullDomain, msg.sender, block.timestamp + DURATION, false, 0, false, address(0), 0, rentTarget, 0, "");

        nameToId[nameHash] = tokenId; // Simpan domain dengan hash
        nameToAddress[nameHash] = msg.sender;

        emit DomainRegistered(fullDomain, msg.sender, block.timestamp + DURATION);

        // Kirim pembayaran ke admin
        payable(admin).transfer(msg.value);
    }

    function transferDomain(string memory name, address to) public onlyOwner(name) {
        uint256 tokenId = nameToId[name];
        domains[tokenId].owner = to;
        nameToAddress[name] = to;

        emit DomainTransferred(name, msg.sender, to);
    }

    function startAuction(string memory name, uint256 minBid) public onlyOwner(name) {
        uint256 tokenId = nameToId[keccak256(abi.encodePacked(name))];
        domains[tokenId].forAuction = true;
        domains[tokenId].minBid = minBid;

        emit DomainAuctionStarted(name, minBid);
    }

    function placeBid(string memory name) public payable {
        uint256 tokenId = nameToId[name];
        require(domains[tokenId].forAuction, "Domain not for auction");
        require(msg.value > auctionHighestBid[tokenId], "Bid too low");

        if (auctionHighestBid[tokenId] > 0) {
        pendingReturns[auctionHighestBidder[tokenId]] += auctionHighestBid[tokenId];
    }
        auctionHighestBidder[tokenId] = msg.sender;
        auctionHighestBid[tokenId] = msg.value;

        emit DomainBidPlaced(name, msg.sender, msg.value);
    }

    function endAuction(string memory name) public onlyOwner(name) {
        uint256 tokenId = nameToId[name];
        require(domains[tokenId].forAuction, "Domain not in auction");

        domains[tokenId].forAuction = false;
        domains[tokenId].owner = auctionHighestBidder[tokenId];
        nameToAddress[name] = auctionHighestBidder[tokenId];

        emit DomainAuctionEnded(name, auctionHighestBidder[tokenId], auctionHighestBid[tokenId]);

        // Kirim hasil lelang ke admin
        payable(admin).transfer(auctionHighestBid[tokenId]);
    }

    function rentDomain(string memory name) public payable {
        uint256 tokenId = nameToId[name];
        require(domains[tokenId].owner != address(0), "Domain not found");
        require(!domains[tokenId].isRented, "Already rented");
        require(msg.value > 0, "Need rent payment");

        domains[tokenId].isRented = true;
        domains[tokenId].renter = msg.sender;
        domains[tokenId].rentPaid += msg.value;

        emit DomainRented(name, msg.sender, msg.value);

        if (domains[tokenId].rentPaid >= domains[tokenId].rentTarget) {
            domains[tokenId].owner = msg.sender;
            domains[tokenId].isRented = false;
            emit RentCompleted(name, msg.sender);
        }

        // Kirim pembayaran ke admin
        payable(admin).transfer(msg.value);
    }

    function isExpired(string memory name) public view returns (bool) {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        return block.timestamp > domains[nameToId[nameHash]].expiry;
    }

    function releaseExpiredDomain(string memory name) public {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        uint256 tokenId = nameToId[nameHash];
        require(isExpired(name), "Domain not expired yet");

        address previousOwner = domains[tokenId].owner;

        delete nameToAddress[nameHash];
        delete nameToId[nameHash];
        delete domains[tokenId];

        emit DomainTransferred(name, previousOwner, address(0));
    }

    function autoExpireRental(string memory name) public {
        uint256 tokenId = nameToId[keccak256(abi.encodePacked(name))];
        require(domains[tokenId].isRented, "Domain not rented");
        require(block.timestamp > domains[tokenId].expiry, "Rental period not over");

        domains[tokenId].isRented = false;
        domains[tokenId].renter = address(0);
    }

    function initiateRecovery(string memory name, address newOwner) public {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        require(domains[nameToId[nameHash]].owner == msg.sender, "Not domain owner");

        pendingRecovery[nameHash] = newOwner;
        emit RecoveryInitiated(nameHash, newOwner);
    }

    function approveRecovery(string memory name) public {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        require(isGuardian(msg.sender, nameHash), "Not a guardian");
        require(pendingRecovery[nameHash] != address(0), "No recovery request");

        guardianApproval[nameHash][msg.sender] = true;
        emit RecoveryApproved(nameHash, msg.sender);

        uint256 approvals = 0;
        for (uint256 i = 0; i < domainGuardians[nameHash].length; i++) {
            if (guardianApproval[nameHash][domainGuardians[nameHash][i]]) {
                approvals++;
            }
        }

        if (approvals >= 3) {
            domains[nameToId[nameHash]].owner = pendingRecovery[nameHash];
            emit RecoveryCompleted(nameHash, pendingRecovery[nameHash]);
            delete pendingRecovery[nameHash];
        }
    }

    function isGuardian(address user, bytes32 nameHash) internal view returns (bool) {
        for (uint256 i = 0; i < domainGuardians[nameHash].length; i++) {
            if (domainGuardians[nameHash][i] == user) {
                return true;
            }
        }
        return false;
    }

    function endAuction(string memory name) public onlyOwner(name) {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        uint256 tokenId = nameToId[nameHash];
        require(domains[tokenId].forAuction, "Domain not in auction");
        require(auctionHighestBidder[tokenId] != address(0), "No valid bids");

        domains[tokenId].forAuction = false;
        domains[tokenId].owner = auctionHighestBidder[tokenId];
        nameToAddress[nameHash] = auctionHighestBidder[tokenId];

        emit DomainAuctionEnded(name, auctionHighestBidder[tokenId], auctionHighestBid[tokenId]);

        // Kirim hasil lelang ke admin
        payable(admin).transfer(auctionHighestBid[tokenId]);
    }

    function setName(string memory name, address userAddress) public {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        require(nameToAddress[nameHash] == address(0), "Name already taken");
        
        nameToAddress[nameHash] = userAddress;
        addressToName[userAddress] = nameHash;
    }

    function resolve(string memory name, string memory extension) public view returns (address) {
        string memory fullDomain = string(abi.encodePacked(name, ".lol", extension));
        bytes32 nameHash = keccak256(abi.encodePacked(fullDomain));
        require(nameToAddress[nameHash] != address(0), "Domain not found");
        return nameToAddress[nameHash];
    }

    function reverseResolve(address userAddress) public view returns (string memory) {
        require(addressToName[userAddress] != 0, "Address not found");
        return string(abi.encodePacked(addressToName[userAddress]));
    }

    function reverseResolve(address userAddress) public view returns (string memory) {
        return string(abi.encodePacked(addressToName[userAddress]));
    }

    function isDomainRegistered(string memory name) public view returns (bool) {
        return domainOwners[name] != address(0);
    }

    function withdraw() public onlyAdmin {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");

        (bool success, ) = admin.call{value: balance}("");
        require(success, "Withdraw failed");

        emit FundsWithdrawn(admin, balance);
    }

    function createSubdomain(string memory mainDomain, string memory subDomain, address owner) public onlyOwner(mainDomain) {
        require(subdomains[mainDomain][subDomain] == address(0), "Subdomain exists");

        subdomains[mainDomain][subDomain] = owner;

        emit SubdomainCreated(mainDomain, subDomain, owner);
    }
}
