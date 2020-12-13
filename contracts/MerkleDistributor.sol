// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.6.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@openzeppelin/contracts/math/SafeMath.sol';
import "@openzeppelin/contracts/cryptography/MerkleProof.sol";
import "./interfaces/IMerkleDistributor.sol";

contract MerkleDistributor is IMerkleDistributor {
    using SafeMath for uint256;
    address public immutable override token;
    bytes32 public immutable override merkleRoot;
    address public immutable override rewardsAddress;
    address public immutable override burnAddress;
    
    // Packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;
    address deployer;

    uint256 public immutable startTime;
    uint256 public immutable endTime;
    uint256 internal immutable secondsInaDay = 86400;

    constructor(address token_, bytes32 merkleRoot_, address rewardsAddress_, address burnAddress_, uint256 startTime_, uint256 endTime_) public {
        token = token_;
        merkleRoot = merkleRoot_;
        rewardsAddress = rewardsAddress_;
        burnAddress = burnAddress_;
        deployer = msg.sender; // the deployer address
        startTime = startTime_;
        endTime = endTime_;
    }

    function isClaimed(uint256 index) public view override returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimedWordIndex] = claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
    }

    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) external override {
        // [P] Uncomment: line below, requiring the claim to originate from the 'account'.
        // require(msg.sender == account, 'MerkleDistributor: Only account may withdraw'); // ensures only account may withdraw on behalf of account
        require(!isClaimed(index), 'MerkleDistributor: Drop already claimed.');

        // VERIFY | MERKLE PROOF
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), 'MerkleDistributor: Invalid proof.');

         // CLAIM AND SEND | TOKEN TO ACCOUNT
        _setClaimed(index);
        uint256 duraTime = now.sub(startTime);
        require(now >= startTime, 'MerkleDistributor: Too soon');
        require(now <= endTime, 'MerkleDistributor: Too late');
        // create a ceiling for the maximum amount of duraTime
        uint256 duraDays = duraTime.div(secondsInaDay); // divided by the number of seconds per day
        require(duraDays <= 100, 'MerkleDistributor: Too late'); // Check days
        uint256 availAmount = amount.mul(duraDays.add(10)).div(100);// 10% + 1% daily
        require(availAmount <= amount, 'MerkleDistributor: Slow your roll');// do not over-distribute
        uint256 foreitedAmount = amount.sub(availAmount);

        require(IERC20(token).transfer(account, availAmount), 'MerkleDistributor: Transfer to Account failed.');
        require(IERC20(token).transfer(rewardAddress, foreitedAmount.div(2)), 'MerkleDistributor: Transfer to rewardAddress failed.');
        require(IERC20(token).transfer(burnAddress, foreitedAmount.div(2)), 'MerkleDistributor: Transfer to burnAddress failed.');

        emit Claimed(index, account, amount);
    }

    function collectDust(address _token, uint256 _amount) external {
      require(msg.sender == deployer, "!deployer");
      require(_token != token, "!token");
      if (_token == address(0)) { // token address(0) = ETH
        payable(deployer).transfer(_amount);
      } else {
        IERC20(_token).transfer(deployer, _amount);
      }
    }
}
