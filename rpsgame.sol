pragma solidity ^0.4.24;

contract Owned {
    address public owner;

    function Owned() public {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function changeOwner(address newOwner) onlyOwner public {
        owner = newOwner;
    }
}

contract Game is Owned {
    using SafeMath for uint256;
    using SafeMath for uint8;
    using SafeMath for uint;

    int8 constant ROCK = 2;
    int8 constant SCISSORS = 1;
    int8 constant PAPER = 0;
    uint8 constant WIN = 100;
    uint8 constant LOSE = 200;
    uint8 constant DRAW = 150;

    // uint256 expireTime = 1 hours; // 可等待匹配时间
    uint256 betTime = 30 minutes; // 下注时间
    uint randomNonce = 0;

    uint8 public maxGame = 0;
    uint8 public remainNum= 0;
    uint8 public betRate = 10;
    uint256 public betMaximum = 5 ether;  //
    uint256 public betMinimum = 1000 wei; //

    uint8[] public remainGames; // 

    struct Game {
        uint createdAt;
        address winner;
        address defender;
        address challenger;
        uint8 status;// 0单人开局  1对局中  2完成
        uint256 betPool;
        uint256 defenderPool;
        uint256 challengerPool;
        mapping(address => mapping(address => uint256)) gameSupporter;
    }

    // 保存出手结果的黑盒子
    struct GameMia {
        int8 defenderGesture;
        int8 challengerGesture;
    }
    
    mapping (uint => Game) public games;
    mapping (uint => GameMia) internal gameMia;
    
    modifier isValidGesture(int gesture) {
        require(gesture == ROCK || gesture == SCISSORS || gesture == PAPER);
        _;
    }

    // event StartGame(address _gamer, int8 gesture, uint gameId);
    event Betlog(address _bet, address _to, uint256 _value);

    // 随机参与，防止传输结果被爬取用于作弊
    // 如果有匹配的局就加入，没有则自建
    function startGame(int8 gesture)
    isValidGesture(gesture)
    public payable
    returns (uint) {
        require(msg.value > betMinimum, "Need mortgage");
        // 随机匹配，至少有5个活动局
        if (remainNum >= 5) {
            randomNonce += 1;
            uint random = uint(keccak256(now, msg.sender, randomNonce)) % remainNum;
            uint j = 0;
            for (uint i=0; i<remainGames.length; i++) {
                // 如果是被delete了，不算
                if (remainGames[i] == 0) {
                    continue;
                }
                if(j == random) {
                    // 匹配成功
                    require(games[remainGames[j]].defender != msg.sender, "challenger & defender should not be same!");
                    game = games[remainGames[j]];
                    game.challenger = msg.sender;
                    game.betPool = game.betPool.add(msg.value);
                    game.status = 1;
                    game.createdAt = now;
                    game.gameSupporter[msg.sender][msg.sender] = msg.value;
                    game.challengerPool = game.challengerPool.add(msg.value);
                    setGameMiaChallenger(remainGames[j], gesture);
                    remainNum -= 1;
                    uint8 finId = remainGames[j];
                    delete remainGames[j];
                    return finId;
                }
                j++;
            }
        } else {
            // 没有匹配则创建
            maxGame += 1;
            remainNum += 1;
            Game storage game = games[maxGame];
            game.defender = msg.sender;
            game.gameSupporter[msg.sender][msg.sender] = msg.value;
            game.betPool = game.betPool.add(msg.value);
            game.defenderPool = game.defenderPool.add(msg.value);
            setGameMiaDefender(maxGame, gesture);
            remainGames.push(maxGame);
            return maxGame;
        }
    }

    // 手势放入黑盒
    function setGameMiaDefender(uint8 gameId, int8 gesture) 
    internal
    returns (bool) {
        gameMia[gameId].defenderGesture = gesture;
    }

    function setGameMiaChallenger(uint8 gameId, int8 gesture) 
    internal
    returns (bool) {
        gameMia[gameId].challengerGesture = gesture;
    }

    // 获取用户下注结果
    function getUserBet(uint8 gameId, address player) view public returns(uint) {
        return games[gameId].gameSupporter[player][msg.sender];
    }

    // 结果比对
    function battle(int8 a, int8 b) 
    isValidGesture(a) isValidGesture(b)
    internal
    view returns(uint8) {
        int8 res = a - b;
        if (res == 0) {
            return DRAW;
        }
        if (res == 1 || res == -2) {
            return WIN;
        }
        if (res == -1 || res == 2) {
            return LOSE;
        }
    }

    // 其他人参与下注
    function bet(uint8 gameId, address player) payable public {
        require(games[gameId].status == 1);
        require(now < games[gameId].createdAt + betTime);
        require(player == games[gameId].defender || player == games[gameId].challenger);
        require(msg.value > betMinimum);
    
        games[gameId].gameSupporter[player][msg.sender] += msg.value;
        games[gameId].betPool = games[gameId].betPool.add(msg.value);
        if (player == games[gameId].defender){
            games[gameId].defenderPool = games[gameId].defenderPool.add(msg.value);
        } else {
            games[gameId].challengerPool = games[gameId].challengerPool.add(msg.value);
        }
        emit Betlog(msg.sender, player, msg.value);
    }

    // 公布结果
    function open(uint8 gameId) public {
        require(games[gameId].status == 1);
        games[gameId].status = 2;
        uint8 res = battle(gameMia[gameId].defenderGesture,gameMia[gameId].challengerGesture);
        if (res == WIN) {
            games[gameId].winner = games[gameId].defender;
        } else if (res == LOSE) {
            games[gameId].winner = games[gameId].challenger;
        }
    }

    // 主动获取奖励
    function getReward(uint8 gameId, address betUser) public {
        require(games[gameId].status == 2);
        uint base;
        if (games[gameId].winner == games[gameId].defender) {
            base = games[gameId].defenderPool;
        } else {
            base = games[gameId].challengerPool;
        }
        if (betUser == games[gameId].winner &&
        games[gameId].gameSupporter[betUser][msg.sender] > 0
        ) {
            uint origin = games[gameId].gameSupporter[betUser][msg.sender];
            uint rerate = percent(origin, base, 3);
            uint reward = games[gameId].betPool * rerate / 100;
            if (reward > 0) {
                msg.sender.transfer(reward);
            }
        }
    }

    // 平局退款
    function getRefund(uint8 gameId, address betUser) public {
        require(games[gameId].status == 2);
        if (games[gameId].winner == address(0)) {
            uint reward = games[gameId].gameSupporter[betUser][msg.sender];
            if (reward > 0) {
                msg.sender.transfer(reward);
            }
        }
    }

    // 未开局前取消
    function cancel(uint gameId) public {
        require(games[gameId].status == 0);
        require(msg.sender == games[gameId].defender);
        // 取消并退款
        msg.sender.transfer(games[gameId].betPool);
        remainNum -= 1;
        for (uint i=0;i<remainGames.length;i++){
            if (gameId == remainGames[i]) {
                delete remainGames[i];
                break;
            }
        }
        delete games[gameId];
    }
    
    // 比例计算
    function percent(uint numerator, uint denominator, uint precision) public 
    constant returns(uint) {
        uint _numerator  = numerator * 10 ** (precision+1);
        uint _quotient =  ((_numerator / denominator) + 5) / 10;
        return ( _quotient);
    }
}


library SafeMath {
    function mul(uint a, uint b) internal pure returns (uint) {
        uint c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    function div(uint a, uint b) internal pure returns (uint) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    function sub(uint a, uint b) internal pure returns (uint) {
        assert(b <= a);
        return a - b;
    }

    function add(uint a, uint b) internal pure returns (uint) {
        uint c = a + b;
        assert(c >= a);
        return c;
    }

    function max64(uint64 a, uint64 b) internal pure returns (uint64) {
        return a >= b ? a : b;
    }

    function min64(uint64 a, uint64 b) internal pure returns (uint64) {
        return a < b ? a : b;
    }

    function max256(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function min256(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
    
}