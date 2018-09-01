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
    uint256 public betMaximun = 5 ether;

    uint8[] public remainGames;

    struct Game {
        uint createdAt;
        address winner;
        address defender;
        address challenger;
        uint8 status;// 0单人开局  1对局中  2完成
        uint256 betPool;
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


    function startGame(int8 gesture)
    isValidGesture(gesture)
    public payable
    returns (uint) {
        require(msg.value > 0, "Need mortgage");
        // 随机匹配
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
                    games[remainGames[j]].challenger = msg.sender;
                    games[remainGames[j]].betPool = games[remainGames[j]].betPool.add(msg.value);
                    games[remainGames[j]].status = 1;
                    games[remainGames[j]].createdAt = now;
                    games[remainGames[j]].gameSupporter[msg.sender][msg.sender] = msg.value;
                    setGameMiaChallenger(remainGames[j], gesture);
                    remainNum -= 1;
                    return remainGames[j];
                }
                j++;
            }
        } else {
            // 没有匹配则创建
            maxGame += 1;
            remainNum += 1;
            Game storage game = games[maxGame];
            game.defender = msg.sender;
            if (msg.value > 0) {
                game.gameSupporter[msg.sender][msg.sender] = msg.value;
                game.betPool = game.betPool.add(msg.value);
                setGameMiaDefender(maxGame, gesture);
            }
            remainGames.push(maxGame);
            return maxGame;
        }
    }

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

    function getUserBet(uint8 gameId, address player) view public returns(uint) {
        return games[gameId].gameSupporter[player][msg.sender];
    }

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

    function bet(uint8 gameId, address player) payable public {
        require(games[gameId].status == 1);
        require(player == games[gameId].defender || player == games[gameId].challenger);
        if (msg.value > 0) {
            games[gameId].gameSupporter[player][msg.sender] += msg.value;
            games[gameId].betPool = games[gameId].betPool.add(msg.value);
        }
    }

    function open(uint8 gameId) public {
        require(games[gameId].status == 1);
        games[gameId].status = 2;
        uint8 res = battle(gameMia[gameId].defenderGesture,gameMia[gameId].challengerGesture);
        if (res == WIN) {
            distribute(gameId, games[gameId].defender);
        }
    }

    function distribute(uint8 gameId, address winner) public {
        
    }

    function cancel(uint gameId) public {
        require(games[gameId].status == 0);
        require(msg.sender == games[gameId].defender);
        // 取消并退款
        msg.sender.transfer(games[gameId].betPool);
        delete games[gameId];

    }

    // function checkInfo(uint gameId) public returns(){
    //     require(games[gameId].status == 2);
    //     return gameMia[gameId];
    // }

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