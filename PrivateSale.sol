pragma solidity 0.4.25;

import './libs/goldpegas/Auth.sol';
import './libs/goldpegas/MerkelProof.sol';
import './libs/zeppelin/math/SafeMath.sol';
import './libs/zeppelin/token/BEP20/IBEP20.sol';
import './libs/zeppelin/token/BEP20/IGDP.sol';

contract PrivateSale is Auth {
  using SafeMath for uint;
  struct User {
    address userAddress;
    uint[] amounts;
  }

  IGDP public gdpToken;
  IBEP20 public usdtToken;

  uint[] public amounts = [0, 1e5, 1e5, 1e5, 1e5, 1e5, 1e5, 1e5, 1e5, 1e5, 1e5, 2e5, 2e5, 2e5, 2e5, 2e5, 3e5, 3e5, 3e5, 3e5, 3e5];
  uint[] public prices = [0, 30e16, 36e16, 42e16, 48e16, 54e16, 60e16, 66e16, 72e16, 78e16, 84e16, 90e16, 96e16, 102e16, 108e16, 114e16, 120e16, 126e16, 132e16, 138e16, 144e16];
  uint[] public sold = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  uint public cap = 1e25;
  uint constant blocksPerRound = 144000; // 5 days
  uint constant totalRound = 20;
  uint constant privateSaleAllocation = 35e23;
  address private usdtHolder;
  uint public roundStartBlock;
  bool public openSale;
  bool public whitelistOpened;
  uint public currentRound = 1;
  bytes32 public rootHash;

  mapping (address => User) private users;

  event Bought(address indexed _user, uint _amount, uint _round);
  event Claimed(address indexed _user, uint _amount);
  event WhiteListUpdated(bool _open);

  constructor(
    address _mainAdmin,
    address _backupAdmin,
    address _usdtHolder,
    address _gdpToken,
    address _busdtToken
  ) public Auth(_mainAdmin, _backupAdmin) {
    usdtHolder = _usdtHolder;
    gdpToken = IGDP(_gdpToken);
    usdtToken = IBEP20(_busdtToken);
  }

  // OWNER FUNCTIONS

  function setRootHash(bytes32 _rootHash) onlyMainAdmin public {
    rootHash = _rootHash;
  }

  function setCap(uint _cap) onlyMainAdmin public {
    cap = _cap;
  }

  function startSale() onlyMainAdmin public {
    openSale = true;
    roundStartBlock = block.number;
  }

  function updateWhiteList(bool _open) onlyMainAdmin public {
    whitelistOpened = _open;
    emit WhiteListUpdated(_open);
  }

  function finish() onlyMainAdmin public {
    uint totalSold;
    for (uint i = 1; i <= totalRound; i++) {
      totalSold = totalSold.add(sold[i]);
    }
    openSale = false;
    gdpToken.burn(privateSaleAllocation.sub(totalSold));
  }

  function updateMainAdmin(address _newMainAdmin) onlyBackupAdmin public {
    require(_newMainAdmin != address(0), 'GDP PrivateSale: invalid mainAdmin address');
    mainAdmin = _newMainAdmin;
  }

  function updateBackupAdmin(address _newBackupAdmin) onlyBackupAdmin public {
    require(_newBackupAdmin != address(0), 'GDP PrivateSale: invalid backupAdmin address');
    backupAdmin = _newBackupAdmin;
  }

  function updateUsdtHolder(address _newUsdtHolder) onlyMainAdmin public {
    require(_newUsdtHolder != address(0), 'GDP PrivateSale: invalid usdtHolder address');
    usdtHolder = _newUsdtHolder;
  }

  // PUBLIC FUNCTIONS

  function buyWhiteList(uint _usdtAmount, bytes32[] _path) public {
    require(openSale, 'GDP PrivateSale: sale is not open!!!');
    require(whitelistOpened, 'GDP PrivateSale: whitelist is not opened!!!');
    bytes32 hash = keccak256(abi.encodePacked(_msgSender()));
    require(MerkleProof.verify(_path, rootHash, hash), 'GDP PrivateSale: 400');
    buy(_usdtAmount);
  }

  function buy(uint _usdtAmount) public {
    require(openSale, 'GDP PrivateSale: sale is not open!!!');
    require(!whitelistOpened, 'GDP PrivateSale: whitelist is opening!!!');
    User storage user = users[_msgSender()];
    if (user.userAddress == address(0)) {
      user.userAddress = _msgSender();
      user.amounts = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    }
    _validateUserCap(user, _usdtAmount);
    _updateRound();
    _buy(user, _usdtAmount);
  }

  function claim() public {
    require(!openSale, 'GDP PrivateSale: sale is not finished!!!');
    User storage user = users[_msgSender()];
    uint userToken;
    for (uint i = 1; i <= totalRound; i++) {
      userToken = userToken.add(user.amounts[i]);
    }
    if (userToken > 0) {
      gdpToken.transfer(user.userAddress, userToken);
      emit Claimed(user.userAddress, userToken);
    }
  }

  // PRIVATE FUNCTIONS

  function _updateRound() private {
    uint blockPassed = block.number - roundStartBlock;
    if (blockPassed > blocksPerRound) {
      uint roundPassed = blockPassed / blocksPerRound;
      if (currentRound + roundPassed <= totalRound) {
        roundStartBlock += (roundPassed * blocksPerRound);
        currentRound += roundPassed;
      }
    }
  }

  function _buy(User storage _user, uint _usdtAmount) private {
    if (_usdtAmount <= 0) {
      return;
    }
    uint tokenLeftInRound = amounts[currentRound] - sold[currentRound];
    uint usdtLeftInRound = tokenLeftInRound * prices[currentRound];
    if (_usdtAmount < usdtLeftInRound) {
      uint willSaleTokenAmount = _usdtAmount * 1e18 / prices[currentRound];
      _user.amounts[currentRound] = _user.amounts[currentRound].add(willSaleTokenAmount);
      sold[currentRound] = sold[currentRound].add(willSaleTokenAmount);
      usdtToken.transferFrom(_msgSender(), address(this), _usdtAmount);
      usdtToken.transfer(usdtHolder, _usdtAmount);
      emit Bought(_user.userAddress, willSaleTokenAmount, currentRound);
    } else {
      _user.amounts[currentRound] = _user.amounts[currentRound].add(tokenLeftInRound);
      sold[currentRound] = sold[currentRound].add(tokenLeftInRound);
      usdtToken.transferFrom(_msgSender(), address(this), usdtLeftInRound);
      usdtToken.transfer(usdtHolder, usdtLeftInRound);
      emit Bought(_user.userAddress, tokenLeftInRound, currentRound);
      if (currentRound == totalRound) {
        return;
      }
      currentRound += 1;
      roundStartBlock = block.number;
      _buy(_user, _usdtAmount - usdtLeftInRound);
    }
  }

  function _validateUserCap(User storage user, uint _usdtAmount) private view {
    uint userSpent;
    for (uint i = 1; i <= totalRound; i++) {
      userSpent = userSpent.add(user.amounts[i].div(1e18).mul(prices[i]));
    }
    require(userSpent.add(_usdtAmount) <= cap, 'GDP PrivateSale: check your cap!!!');
  }
}
