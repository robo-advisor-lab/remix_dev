interface ERC20:
    def transfer(recipient: address, amount: uint256): nonpayable
    def balanceOf() -> uint256: view

event Deposit:
    user: indexed(address)
    amount: uint256

struct Deposits:
    user: address
    amount: uint256

deposits: DynArray[Deposits, 128]
balances: public(HashMap[address, uint256])

@external
@payable
def deposit():
    self.deposits.append(Deposits({user: msg.sender, amount: msg.value}))
    log Deposit(msg.sender, msg.value)
    self.balances[msg.sender] += msg.value