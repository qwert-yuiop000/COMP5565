// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract DecentralizedProductProvenance {
    address public admin;
    
    // Role management
    mapping(address => Role) public roles;
    mapping(address => bool) public authorizedServiceCenters;
    
    // Enum definitions
    enum Role { None, Manufacturer, Retailer, Customer, ServiceCenter }
    enum WarrantyStatus { Active, Expired, Revoked, ClaimLimitReached }
    enum ClaimStatus { Pending, Approved, Rejected, Completed }
    
    // Event definitions
    event ProductRegistered(string indexed productId, address manufacturer);
    event OwnershipTransferred(string indexed productId, address from, address to, Role fromRole, Role toRole, string details);
    event WarrantyClaimSubmitted(string indexed productId, uint256 claimId, address customer);
    event WarrantyClaimProcessed(string indexed productId, uint256 claimId, ClaimStatus status, address serviceCenter);
    event WarrantyStatusChanged(string indexed productId, WarrantyStatus newStatus);
    event RoleAssigned(address user, Role role);
    
    // Product structure
    struct Product {
        string productId;
        string serialNumber;
        string model;
        string specifications;
        address manufacturer;
        address currentOwner;
        uint256 manufactureTimestamp;
        WarrantyInfo warranty;
        bool exists;
    }
    
    // Warranty information structure
    struct WarrantyInfo {
        uint256 startDate;
        uint256 duration;
        uint256 maxClaims;
        uint256 usedClaims;
        WarrantyStatus status;
    }
    
    // Ownership record structure
    struct OwnershipRecord {
        address owner;
        Role role;
        uint256 transferTimestamp;
        string transactionDetails;
        bool isVisible;
    }
    
    // Warranty claim structure
    struct WarrantyClaim {
        uint256 claimId;
        address customer;
        address serviceCenter;
        string description;
        string serviceNotes;
        uint256 submitTimestamp;
        uint256 processTimestamp;
        ClaimStatus status;
        bool isVisible;
    }
    
    // Storage mappings
    mapping(string => Product) public products;
    mapping(string => OwnershipRecord[]) public ownershipHistory;
    mapping(string => WarrantyClaim[]) public warrantyClaims;
    mapping(address => string[]) public userProducts;
    mapping(string => mapping(address => bool)) public productVisibility;
    
    // Modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }
    
    modifier onlyManufacturer() {
        require(roles[msg.sender] == Role.Manufacturer, "Only manufacturer can perform this action");
        _;
    }
    
    modifier onlyRetailer() {
        require(roles[msg.sender] == Role.Retailer, "Only retailer can perform this action");
        _;
    }
    
    modifier onlyCustomer() {
        require(roles[msg.sender] == Role.Customer, "Only customer can perform this action");
        _;
    }
    
    modifier onlyServiceCenter() {
        require(authorizedServiceCenters[msg.sender], "Only authorized service center can perform this action");
        _;
    }
    
    modifier productExists(string memory productId) {
        require(products[productId].exists, "Product does not exist");
        _;
    }
    
    modifier onlyProductOwner(string memory productId) {
        require(products[productId].currentOwner == msg.sender, "Only product owner can perform this action");
        _;
    }
    
    constructor() {
        admin = msg.sender;
    }
    
    // ========== ROLE MANAGEMENT FUNCTIONS ==========
    
    function assignRole(address user, Role role) external onlyAdmin {
        require(user != address(0), "Invalid user address");
        roles[user] = role;
        
        if (role == Role.ServiceCenter) {
            authorizedServiceCenters[user] = true;
        }
        
        emit RoleAssigned(user, role);
    }
    
    function addServiceCenter(address serviceCenter) external onlyAdmin {
        authorizedServiceCenters[serviceCenter] = true;
        roles[serviceCenter] = Role.ServiceCenter;
    }
    
    // ========== MANUFACTURER FUNCTIONS ==========
    
    function registerProduct(
        string memory productId,
        string memory serialNumber,
        string memory model,
        string memory specifications,
        uint256 warrantyDuration,
        uint256 maxWarrantyClaims
    ) external onlyManufacturer {
        require(!products[productId].exists, "Product already exists");
        require(bytes(productId).length > 0, "Product ID cannot be empty");
        require(warrantyDuration > 0, "Warranty duration must be positive");
        
        WarrantyInfo memory warranty = WarrantyInfo({
            startDate: block.timestamp,
            duration: warrantyDuration * 1 days,
            maxClaims: maxWarrantyClaims,
            usedClaims: 0,
            status: WarrantyStatus.Active
        });
        
        products[productId] = Product({
            productId: productId,
            serialNumber: serialNumber,
            model: model,
            specifications: specifications,
            manufacturer: msg.sender,
            currentOwner: msg.sender,
            manufactureTimestamp: block.timestamp,
            warranty: warranty,
            exists: true
        });
        
        ownershipHistory[productId].push(OwnershipRecord({
            owner: msg.sender,
            role: Role.Manufacturer,
            transferTimestamp: block.timestamp,
            transactionDetails: "Initial manufacturing",
            isVisible: true
        }));
        
        userProducts[msg.sender].push(productId);
        
        emit ProductRegistered(productId, msg.sender);
    }
    
    function transferToRetailer(
        string memory productId,
        address retailer,
        string memory transactionDetails
    ) external onlyManufacturer productExists(productId) onlyProductOwner(productId) {
        require(roles[retailer] == Role.Retailer, "Target must be a retailer");
        _transferOwnership(productId, retailer, Role.Retailer, transactionDetails);
    }
    
    // ========== RETAILER FUNCTIONS ==========
    
    function sellToCustomer(
        string memory productId,
        address customer,
        string memory transactionDetails
    ) external onlyRetailer productExists(productId) onlyProductOwner(productId) {
        require(roles[customer] == Role.Customer, "Target must be a customer");
        _transferOwnership(productId, customer, Role.Customer, transactionDetails);
        
        if (products[productId].warranty.status == WarrantyStatus.Active) {
            products[productId].warranty.startDate = block.timestamp;
        }
    }
    
    // ========== CUSTOMER FUNCTIONS ==========
    
    function verifyProductOwnership(string memory productId) external view productExists(productId) returns (bool isOwner, bool isAuthentic, address currentOwner, address manufacturer) {
        Product memory product = products[productId];
        isOwner = (product.currentOwner == msg.sender);
        isAuthentic = (product.manufacturer != address(0));
        currentOwner = product.currentOwner;
        manufacturer = product.manufacturer;
        return (isOwner, isAuthentic, currentOwner, manufacturer);
    }
    
    function submitWarrantyClaim(string memory productId, string memory description) external onlyCustomer productExists(productId) onlyProductOwner(productId) returns (uint256) {
        Product storage product = products[productId];
        WarrantyInfo storage warranty = product.warranty;
        
        require(warranty.status == WarrantyStatus.Active, "Warranty is not active");
        require(block.timestamp <= warranty.startDate + warranty.duration, "Warranty has expired");
        require(warranty.usedClaims < warranty.maxClaims, "Warranty claim limit reached");
        
        uint256 claimId = warrantyClaims[productId].length;
        
        warrantyClaims[productId].push(WarrantyClaim({
            claimId: claimId,
            customer: msg.sender,
            serviceCenter: address(0),
            description: description,
            serviceNotes: "",
            submitTimestamp: block.timestamp,
            processTimestamp: 0,
            status: ClaimStatus.Pending,
            isVisible: true
        }));
        
        emit WarrantyClaimSubmitted(productId, claimId, msg.sender);
        return claimId;
    }
    
    function resellProduct(string memory productId, address newOwner, string memory transactionDetails) external onlyCustomer productExists(productId) onlyProductOwner(productId) {
        require(roles[newOwner] == Role.Customer, "Target must be a customer");
        _transferOwnership(productId, newOwner, Role.Customer, transactionDetails);
    }
    
    function setProductVisibility(string memory productId, bool isVisible) external onlyCustomer productExists(productId) onlyProductOwner(productId) {
        productVisibility[productId][msg.sender] = isVisible;
    }
    
    // ========== SERVICE CENTER FUNCTIONS ==========
    
    function processWarrantyClaim(string memory productId, uint256 claimId, ClaimStatus status, string memory serviceNotes) external onlyServiceCenter productExists(productId) {
        require(claimId < warrantyClaims[productId].length, "Invalid claim ID");
        
        WarrantyClaim storage claim = warrantyClaims[productId][claimId];
        Product storage product = products[productId];
        WarrantyInfo storage warranty = product.warranty;
        
        require(claim.status == ClaimStatus.Pending, "Claim already processed");
        
        claim.status = status;
        claim.serviceCenter = msg.sender;
        claim.serviceNotes = serviceNotes;
        claim.processTimestamp = block.timestamp;
        
        if (status == ClaimStatus.Approved) {
            warranty.usedClaims++;
            if (warranty.usedClaims >= warranty.maxClaims) {
                warranty.status = WarrantyStatus.ClaimLimitReached;
                emit WarrantyStatusChanged(productId, WarrantyStatus.ClaimLimitReached);
            }
        }
        
        emit WarrantyClaimProcessed(productId, claimId, status, msg.sender);
    }
    
    function logServiceAction(string memory productId, string memory serviceDescription, string memory partsReplaced) external onlyServiceCenter productExists(productId) {
        uint256 claimId = warrantyClaims[productId].length;
        
        warrantyClaims[productId].push(WarrantyClaim({
            claimId: claimId,
            customer: products[productId].currentOwner,
            serviceCenter: msg.sender,
            description: serviceDescription,
            serviceNotes: partsReplaced,
            submitTimestamp: block.timestamp,
            processTimestamp: block.timestamp,
            status: ClaimStatus.Completed,
            isVisible: true
        }));
    }
    
    // ========== QUERY FUNCTIONS ==========
    
    function getProductDetails(string memory productId) external view productExists(productId) returns (string memory, string memory, string memory, address, address, uint256, WarrantyInfo memory, bool) {
        Product memory product = products[productId];
        bool isVisible = (product.currentOwner == msg.sender) || productVisibility[productId][product.currentOwner] || msg.sender == admin;
        
        if (!isVisible) {
            return ("***", product.model, "***", product.manufacturer, address(0), product.manufactureTimestamp, product.warranty, false);
        }
        
        return (product.serialNumber, product.model, product.specifications, product.manufacturer, product.currentOwner, product.manufactureTimestamp, product.warranty, true);
    }
    
    function getOwnershipHistory(string memory productId) external view productExists(productId) returns (OwnershipRecord[] memory) {
        OwnershipRecord[] storage allRecords = ownershipHistory[productId];
        uint256 visibleCount = 0;
        
        for (uint256 i = 0; i < allRecords.length; i++) {
            if (allRecords[i].isVisible || msg.sender == admin || products[productId].currentOwner == msg.sender) {
                visibleCount++;
            }
        }
        
        OwnershipRecord[] memory visibleRecords = new OwnershipRecord[](visibleCount);
        uint256 currentIndex = 0;
        
        for (uint256 i = 0; i < allRecords.length; i++) {
            if (allRecords[i].isVisible || msg.sender == admin || products[productId].currentOwner == msg.sender) {
                visibleRecords[currentIndex] = allRecords[i];
                currentIndex++;
            }
        }
        
        return visibleRecords;
    }
    
    function getWarrantyHistory(string memory productId) external view productExists(productId) returns (WarrantyClaim[] memory) {
        WarrantyClaim[] storage allClaims = warrantyClaims[productId];
        uint256 visibleCount = 0;
        
        for (uint256 i = 0; i < allClaims.length; i++) {
            if (allClaims[i].isVisible || msg.sender == admin || products[productId].currentOwner == msg.sender) {
                visibleCount++;
            }
        }
        
        WarrantyClaim[] memory visibleClaims = new WarrantyClaim[](visibleCount);
        uint256 currentIndex = 0;
        
        for (uint256 i = 0; i < allClaims.length; i++) {
            if (allClaims[i].isVisible || msg.sender == admin || products[productId].currentOwner == msg.sender) {
                visibleClaims[currentIndex] = allClaims[i];
                currentIndex++;
            }
        }
        
        return visibleClaims;
    }
    
    function checkWarrantyStatus(string memory productId) external view productExists(productId) returns (WarrantyStatus status, uint256 remainingClaims, uint256 expiryDate) {
        Product memory product = products[productId];
        WarrantyInfo memory warranty = product.warranty;
        
        if (warranty.status == WarrantyStatus.Active && block.timestamp > warranty.startDate + warranty.duration) {
            status = WarrantyStatus.Expired;
        } else {
            status = warranty.status;
        }
        
        remainingClaims = warranty.maxClaims - warranty.usedClaims;
        expiryDate = warranty.startDate + warranty.duration;
        
        return (status, remainingClaims, expiryDate);
    }
    
    // ========== INTERNAL FUNCTIONS ==========
    
    function _transferOwnership(string memory productId, address newOwner, Role newRole, string memory transactionDetails) internal {
        Product storage product = products[productId];
        address previousOwner = product.currentOwner;
        Role previousRole = roles[previousOwner];
        
        product.currentOwner = newOwner;
        
        ownershipHistory[productId].push(OwnershipRecord({
            owner: newOwner,
            role: newRole,
            transferTimestamp: block.timestamp,
            transactionDetails: transactionDetails,
            isVisible: true
        }));
        
        _removeFromUserProducts(previousOwner, productId);
        userProducts[newOwner].push(productId);
        
        emit OwnershipTransferred(productId, previousOwner, newOwner, previousRole, newRole, transactionDetails);
    }
    
    function _removeFromUserProducts(address user, string memory productId) internal {
        string[] storage userProds = userProducts[user];
        for (uint256 i = 0; i < userProds.length; i++) {
            if (keccak256(bytes(userProds[i])) == keccak256(bytes(productId))) {
                userProds[i] = userProds[userProds.length - 1];
                userProds.pop();
                break;
            }
        }
    }
    
    function updateWarrantyStatus(string memory productId) external productExists(productId) {
        Product storage product = products[productId];
        WarrantyInfo storage warranty = product.warranty;
        
        if (warranty.status == WarrantyStatus.Active && block.timestamp > warranty.startDate + warranty.duration) {
            warranty.status = WarrantyStatus.Expired;
            emit WarrantyStatusChanged(productId, WarrantyStatus.Expired);
        }
    }
    
    function getUserProducts(address user) external view returns (string[] memory) {
        return userProducts[user];
    }
    
    function getRole(address user) external view returns (Role) {
        return roles[user];
    }
    
    function isServiceCenter(address user) external view returns (bool) {
        return authorizedServiceCenters[user];
    }
}