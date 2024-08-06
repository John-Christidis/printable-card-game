-include .env
# Variables
NETWORK ?= anvil

# Determine RPC URL based on NETWORK variable
ifeq ($(NETWORK), sepolia)
	RPC_URL = $(SEPOLIA_RPC_URL)
    ACCOUNT = $(SEPOLIA_ACCOUNT)
	SENDER = $(SEPOLIA_DEPLOYER_ADDRESS)	
	VERIFY_API_KEY = $(SEPOLIA_ETHERSCAN_API_KEY)
	PCG_FACTORY = $(SEPOLIA_PCG_FACTORY_ADDRESS)
	PCG_ENGINE = $(SEPOLIA_PCG_ENGINE_ADDRESS)
else ifeq ($(NETWORK), amoy)
    RPC_URL = $(AMOY_RPC_URL)
    ACCOUNT = $(AMOY_ACCOUNT)
	SENDER = $(AMOY_DEPLOYER_ADDRESS)
	VERIFY_API_KEY = $(AMOY_OKLINK_API_KEY)
	PCG_FACTORY = $(AMOY_PCG_FACTORY_ADDRESS)
	PCG_ENGINE = $(AMOY_PCG_ENGINE_ADDRESS)
	NETWORK = polygon-amoy
else ifeq ($(NETWORK), anvil)
    RPC_URL = $(ANVIL_RPC_URL)
    ACCOUNT = $(ANVIL_ACCOUNT)
	SENDER = $(ANVIL_DEPLOYER_ADDRESS)
	PCG_FACTORY = $(ANVIL_PCG_FACTORY_ADDRESS)
	PCG_ENGINE = $(ANVIL_PCG_ENGINE_ADDRESS)
	VRF_WRAPPER = $(ANVIL_VRF_WRAPPER_ADDRESS)
else
	NETWORK = anvil
    RPC_URL = $(ANVIL_RPC_URL)
    ACCOUNT = $(ANVIL_ACCOUNT)
	SENDER = $(ANVIL_DEPLOYER_ADDRESS)
	PCG_FACTORY = $(ANVIL_PCG_FACTORY_ADDRESS)
	PCG_ENGINE = $(ANVIL_PCG_ENGINE_ADDRESS)
	VRF_WRAPPER = $(ANVIL_VRF_WRAPPER_ADDRESS)
endif

clean:
	@echo "Cleaning..."
	forge clean

build:
	@echo "Compiling smart contracts..."
	forge build

compile:
	@echo "Compiling smart contracts..."
	forge compile

test-all:
	@echo "Running tests..."
	forge test --fork-url $(RPC_URL) $(V)
	@echo "Process completed"

test-spec:
	@echo "Running $(TEST)..."
	forge test --fork-url $(RPC_URL) --mt=$(TEST) $(V)
	@echo "Process completed"

coverage:
	@echo "Running tests with coverage..."
	forge coverage --fork-url $(RPC_URL) $(V)
	@echo "Process completed"

test-gas:
	@echo "Running tests with gas report..."
	@echo "Remember to set WITH_GAS_REPORT equal to true in the env file"
	forge test --gas-report --fork-url $(RPC_URL) $(V)
	@echo "Process completed"
	

deploy:
	@echo "Starting process: Deploy PCG Contracts to $(NETWORK) network"
	@echo "Deploying PCG Contracts to $(NETWORK) network..."
	@if [ "$(NETWORK)" = "anvil" ]; then \
		echo "Using $(NETWORK) parameters"; \
		forge script script/DeployPCGContracts.s.sol:DeployPCGContracts --rpc-url $(RPC_URL) --account $(ACCOUNT) --sender $(SENDER) --broadcast $(V); \
	else \
		echo "Using $(NETWORK) parameters"; \
		forge script script/DeployPCGContracts.s.sol:DeployPCGContracts --rpc-url $(RPC_URL) --account $(ACCOUNT) --sender $(SENDER) --broadcast --verify --etherscan-api-key $(VERIFY_API_KEY) $(V); \
	fi
	@echo "Process completed"


deploy-expansion:
	@echo "Starting process: Deploy PCG Expansion to $(NETWORK) network..."
	@echo "Factory $(PCG_FACTORY)"
	@if [ "$(NETWORK)" = "anvil" ]; then \
		echo "Using anvil parameters..."; \
		forge script script/DeployPCGExpansion.s.sol:DeployPCGExpansion --rpc-url $(RPC_URL) --account $(ACCOUNT) --sender $(SENDER) --sig "run(address, string, uint256)" $(PCG_FACTORY) $(CID) $(NOMC) --broadcast $(V); \
	else \
		echo "Using $(NETWORK) parameters..."; \
		forge script script/DeployPCGExpansion.s.sol:DeployPCGExpansion --rpc-url $(RPC_URL) --account $(ACCOUNT) --sender $(SENDER) --sig "run(address, string, uint256)" $(PCG_FACTORY) $(CID) $(NOMC) --broadcast --verify --etherscan-api-key $(VERIFY_API_KEY) $(V); \
	fi 
	@echo "Process completed"

verify-pcg:
	@if [ "$(NETWORK)" = "anvil" ]; then \
		echo "Verifying can only happen on a live or test network, not on a local network"; \
	else \
		echo "Starting process: Verifying PCG Expansion to $(NETWORK) network..."; \
		PCG_CONTRACT_ADDRESS=$$(cast call --rpc-url $(RPC_URL) $(PCG_FACTORY) "getPcg(uint256)(address)" $(PCG_ID)); \
		NUMBER_OF_MINTABLE_CARDS=$$(cast call --rpc-url $(RPC_URL) $$PCG_CONTRACT_ADDRESS "getNumberOfMintableCards()(uint256)"); \
		EXPANSION_ID=$$(cast call --rpc-url $(RPC_URL) $$PCG_CONTRACT_ADDRESS "getExpansion()(uint256)"); \
		URI=$$(cast call --rpc-url $(RPC_URL) $$PCG_CONTRACT_ADDRESS "uri(uint256)(string)" 0); \
		forge verify-contract --chain $(NETWORK) $$PCG_CONTRACT_ADDRESS PCG --constructor-args $$(cast abi-encode "constructor(string,address,uint256,uint256)" "$$URI" $(PCG_ENGINE) $$EXPANSION_ID $$NUMBER_OF_MINTABLE_CARDS) --etherscan-api-key $(VERIFY_API_KEY) --watch; \
	fi

# PCG Factory call functions
call-factory-owner:
	cast call --rpc-url $(RPC_URL) $(PCG_FACTORY) "owner()(address)"

call-factory-get-pcg:
	cast call --rpc-url $(RPC_URL) $(PCG_FACTORY) "getPcg(uint256)(address)" $(PCG_ID)

call-factory-get-pcg-counter:
	cast call --rpc-url $(RPC_URL) $(PCG_FACTORY) "getPcgCounter()(uint256)"

call-factory-get-engine:
	cast call --rpc-url $(RPC_URL) $(PCG_FACTORY) "getPcgEngine()(address)"

# PCG Engine call functions
call-engine-estimate-cards-price:
	cast call --rpc-url $(RPC_URL) $(PCG_ENGINE) "estimatePcgCardsPrice(uint32,uint96)(uint32,uint256,uint256,uint256)" $(NUMBER_OF_CARDS) $(GAS_PRICE)

call-engine-get-purchase:
	cast call --rpc-url $(RPC_URL) $(PCG_ENGINE) "getPurchase(uint256)(address,address,bool)" $(PURCHASE_ID)

call-engine-get-vrf-config:
	cast call --rpc-url $(RPC_URL) $(PCG_ENGINE) "getVrfConfig()(address,uint32,uint16)"

call-engine-get-price-feed-addresses:
	cast call --rpc-url $(RPC_URL) $(PCG_ENGINE) "getPriceFeedAddresses()(address,address)"

call-engine-get-last-price-conversion:
	cast call --rpc-url $(RPC_URL) $(PCG_ENGINE) "getLastPriceConverstion()(uint256)"

call-engine-get-factory-address:
	cast call --rpc-url $(RPC_URL) $(PCG_ENGINE) "getPcgFactoryAddress()(address)"

call-engine-get-card-price:
	cast call --rpc-url $(RPC_URL) $(PCG_ENGINE) "getCardPrice()(uint256)"

call-engine-get-max-card-purchase-limit:
	cast call --rpc-url $(RPC_URL) $(PCG_ENGINE) "getMaxCardPurchaseLimit()(uint32)"

call-engine-get-min-card-purchase-limit:
	cast call --rpc-url $(RPC_URL) $(PCG_ENGINE) "getMinCardPurchaseLimit()(uint32)"

# PCG Engine send functions
send-engine-purchase-cards:
	cast send --rpc-url $(RPC_URL) $(PCG_ENGINE) --account $(ACCOUNT) "purchasePcgCards(uint256,uint32)" $(PCG_ID) $(NUMBER_OF_CARDS) --value $(VALUE)

send-engine-withdraw:
	cast send --rpc-url $(RPC_URL) $(PCG_ENGINE) --account $(ACCOUNT) "withdraw()"

# VRF Wrapper Mock send functions
send-wrapper-fulfill-randomness:
	@if [ "$(NETWORK)" = "anvil" ]; then \
		cast send --rpc-url $(RPC_URL) $(VRF_WRAPPER) --account $(ACCOUNT) "triggerFulfillRandomness(uint256, uint256[])" $(REQUEST_ID) $(RANDOM_WORDS); \
	else \
		echo "send-wrapper-fulfill-randomness can only be used in anvil"; \
	fi

# PCG Expansions call functions
call-pcg-balance-of:
	@PCG_CONTRACT_ADDRESS=$$(cast call --rpc-url $(RPC_URL) $(PCG_FACTORY) "getPcg(uint256)(address)" $(PCG_ID)); \
	cast call --rpc-url $(RPC_URL) $$PCG_CONTRACT_ADDRESS "balanceOf(address, uint256)(uint256)" $(ACCOUNT) $(CARD_ID)

call-pcg-get-number-of-mintable-cards:
	@PCG_CONTRACT_ADDRESS=$$(cast call --rpc-url $(RPC_URL) $(PCG_FACTORY) "getPcg(uint256)(address)" $(PCG_ID)); \
	cast call --rpc-url $(RPC_URL) $$PCG_CONTRACT_ADDRESS "getNumberOfMintableCards()(uint256)" 

call-pcg-get-expansion:
	@PCG_CONTRACT_ADDRESS=$$(cast call --rpc-url $(RPC_URL) $(PCG_FACTORY) "getPcg(uint256)(address)" $(PCG_ID)); \
	cast call --rpc-url $(RPC_URL) $$PCG_CONTRACT_ADDRESS "getExpansion()(uint256)" 

call-pcg-get-uri:
	@PCG_CONTRACT_ADDRESS=$$(cast call --rpc-url $(RPC_URL) $(PCG_FACTORY) "getPcg(uint256)(address)" $(PCG_ID)); \
	cast call --rpc-url $(RPC_URL) $$PCG_CONTRACT_ADDRESS "uri(uint256)(string)" 0

help:
	@echo "==============================Commands for testing and deployment================================"
	@echo "================================================================================================="
	@echo "	make deploy                  - Deployes the PCG Factory along with the PCG Engine"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "     param: V(optional)       value= -v,-vv,-vvv,-vvvv,-vvvvv,-vvvvvv"
	@echo "=================================================================================================="
	@echo " make deploy-expansion        - Deployes a new PCG Expansion from PCG Factory"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "     param: V(optional)       value= -v,-vv,-vvv,-vvvv,-vvvvv,-vvvvvv" 
	@echo "     param: CID               value= string used for the uri of the PCG Expansion"
	@echo "     param: NOMC              value= uint256 number of mintable cards of the PCG Expansion"
	@echo "     param: PCG_FACTORY(optional)  PCG_ENGINE in the env file(default)"
	@echo "            value= address of the PCG Factory to deploy the expansion"
	@echo "=================================================================================================="
	@echo " make verify-pcg              - Verifies an unverified PCG contract"
	@echo "     param: NETWORK           value= sepolia, amoy, anvil(default but it will be skipped)"
	@echo "     param: PCG_ID            value= value= uint256, ID of the PCG to be verified"
	@echo "=================================================================================================="
	@echo " make clean                   - Clean the build directory"
	@echo "=================================================================================================="
	@echo " make build                   - Compiles smart contracts"
	@echo "=================================================================================================="
	@echo " make compile                 - Compiles smart contracts"
	@echo "=================================================================================================="
	@echo " make test-all                - Runs all tests"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "     param: V(optional)       value= -v,-vv,-vvv,-vvvv,-vvvvv,-vvvvvv"
	@echo "=================================================================================================="
	@echo " make test-spec               - Runs a specific test"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "     param: TEST(required)    Name of the test to run"
	@echo "     param: V(optional)       value= -v,-vv,-vvv,-vvvv,-vvvvv,-vvvvvv"
	@echo "=================================================================================================="
	@echo " make coverage                - Runs tests with coverage"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "     param: V(optional)       value= -v,-vv,-vvv,-vvvv,-vvvvv,-vvvvvv"
	@echo "=================================================================================================="
	@echo " make test-gas                - Runs tests with gas report"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "     param: V(optional)       value= -v,-vv,-vvv,-vvvv,-vvvvv,-vvvvvv"
	@echo "     Remember to set WITH_GAS_REPORT equal to true in the env file"
	@echo "=================================================================================================="
	@echo " make help-factory            - Returns all the functions that can be used from PCG Factory"
	@echo "=================================================================================================="
	@echo " make help-engine             - Returns all the functions that can be used from PCG Engine"
	@echo "=================================================================================================="
	@echo " make help-pcg-expansion      - Returns all the functions that can be used from any PCG expansion"
	@echo "=================================================================================================="
	@echo " make help-me-start           - Helps you to start playing with the contracts"
	@echo "=================================================================================================="


help-factory:
	@echo "==================================PCG Factory functions==========================================="
	@echo "=================================================================================================="
	@echo "call-factory-owner"
	@echo "		param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "Call the owner function on PCG Factory"
	@echo "=================================================================================================="
	@echo "call-factory-get-pcg"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "     param: PCG_ID            value= uint256, id of the PCG Expansion"
	@echo "Returns the address of the PCG Expansion with id equal to the one inserted"
	@echo "=================================================================================================="
	@echo "call-factory-get-pcg-counter"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "Returns the number of PCG Expansions created plus one"
	@echo "=================================================================================================="
	@echo "call-factory-get-engine"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "Returns the address of the PCG Engine"
	@echo "=================================================================================================="

help-engine:
	@echo "==================================PCG Engine functions============================================"
	@echo "=================================================================================================="
	@echo "call-engine-estimate-cards-price"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "     param: NUMBER_OF_CARDS   value= uint32, number of cards"
	@echo "     param: GAS_PRICE         value= uint96, gas price in wei"
	@echo "Estimates the price of purchasing the specified number of PCG cards"
	@echo "=================================================================================================="
	@echo "call-engine-get-purchase"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "     param: PURCHASE_ID       value= uint256, ID of the purchase"
	@echo "Returns the details of a specific purchase"
	@echo "=================================================================================================="
	@echo "call-engine-get-vrf-config"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "Returns the VRF configuration"
	@echo "=================================================================================================="
	@echo "call-engine-get-price-feed-addresses"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "Returns the addresses of the price feeds"
	@echo "=================================================================================================="
	@echo "call-engine-get-last-price-conversion"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "Returns the last price conversion"
	@echo "=================================================================================================="
	@echo "call-engine-get-factory-address"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "Returns the address of the PCG Factory"
	@echo "=================================================================================================="
	@echo "call-engine-get-card-price"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "Returns the price of a single card"
	@echo "=================================================================================================="
	@echo "call-engine-get-max-card-purchase-limit"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "Returns the maximum number of cards that can be purchased in a single transaction"
	@echo "=================================================================================================="
	@echo "call-engine-get-min-card-purchase-limit"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "Returns the minimum number of cards that can be purchased in a single transaction"
	@echo "=================================================================================================="
	@echo "send-engine-purchase-cards"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "     param: PCG_ID            value= uint256, ID of the PCG"
	@echo "     param: NUMBER_OF_CARDS   value= uint32, number of cards to purchase"
	@echo "     param: VALUE             value= uint256, amount of ether to send"
	@echo "Purchases the specified number of PCG cards"
	@echo "=================================================================================================="
	@echo "send-engine-withdraw"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "Withdraws funds from the contract"
	@echo "=================================================================================================="
	@echo "==================================VRF Wrapper functions==========================================="
	@echo "These functions can only be called in Anvil or any other local chain and only for testing"
	@echo "=================================================================================================="
	@echo "send-wrapper-fulfill-randomness"
	@echo "     param: NETWORK(optional) value= anvil(default)"
	@echo "     param: REQUEST_ID        value= uint256, ID of the request for randomness"
	@echo "     param: RANDOM_WORDS      value= list of uint256 e.g. [2345, 10, 53432422]"
	@echo "Returns the list to the requested randomness"
	@echo "=================================================================================================="

help-pcg-expansion:
	@echo "==================================PCG Expansion functions========================================="
	@echo "=================================================================================================="
	@echo "call-pcg-balance-of"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "     param: PCG_ID            value= uint256, ID of the PCG"
	@echo "     param: CARD_ID           value= uint256, ID of the card"
	@echo "Returns the balance of the specified card for the given account"
	@echo "=================================================================================================="
	@echo "call-pcg-get-number-of-mintable-cards"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "     param: PCG_ID            value= uint256, ID of the PCG"
	@echo "Returns the number of mintable cards for the specified PCG"
	@echo "=================================================================================================="
	@echo "call-pcg-get-expansion"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "     param: PCG_ID            value= uint256, ID of the PCG"
	@echo "Returns the expansion id of the specified PCG"
	@echo "=================================================================================================="
	@echo "call-pcg-get-uri"
	@echo "     param: NETWORK(optional) value= sepolia, amoy, anvil(default)"
	@echo "     param: PCG_ID            value= uint256, ID of the PCG"
	@echo "Returns the expansion URI of the specified PCG"
	@echo "=================================================================================================="


help-me-start:
	@echo "1. Start anvil by opening a new terminal and type 'anvil'"
	@echo "2. Encrypt the private keys you will be using with the following command"
	@echo "    cast wallet import [YOUR-KEY-NAME] --interactive"
	@echo "Do that process for Anvil, Sepolia and Amoy accounts"
	@echo "3. Make a env file"
	@echo "4. Add the following variables to the env"
	@echo "=================================================================="
	@echo "============================ANVIL================================="
	@echo ""
	@echo "		ANVIL_RPC_URL=http://127.0.0.1:8545"
	@echo "     ANVIL_DEPLOYER_ADDRESS=[Add the address of the encrypted key for ANVIL]"
	@echo "     ANVIL_ACCOUNT=[ANVIL-KEY-NAME]"
	@echo ""
	@echo "     ANVIL_VRF_WRAPPER_ADDRESS=[Fill this later]"
	@echo ""
	@echo "     ANVIL_PCG_FACTORY_ADDRESS=[Fill this later]"
	@echo "     ANVIL_PCG_ENGINE_ADDRESS=[Fill this later]"
	@echo ""
	@echo "=================================================================="
	@echo "============================SEPOLIA==============================="
	@echo ""
	@echo "     SEPOLIA_RPC_URL=https://<your-sepolia-api-key>"
	@echo "     SEPOLIA_ETHERSCAN_API_KEY=<your-sepolia-etherscan-api-key>"
	@echo "     SEPOLIA_DEPLOYER_ADDRESS=[Add the address of the encrypted key for SEPOLIA]"
	@echo "     SEPOLIA_ACCOUNT=[SEPOLIA-KEY-NAME]"
	@echo ""
	@echo "     SEPOLIA_NATIVE_TO_USD_PRICEFEED_ADDRESS=0x694AA1769357215DE4FAC081bf1f309aDC325306"
	@echo "     SEPOLIA_EUR_TO_USD_PRICEFEED_ADDRESS=0x1a81afB8146aeFfCFc5E50e8479e826E7D55b910"
	@echo "     SEPOLIA_VRF_WRAPPER_ADDRESS=0x195f15F2d49d693cE265b4fB0fdDbE15b1850Cc1"
	@echo ""
	@echo "     SEPOLIA_PCG_FACTORY_ADDRESS=[Fill this later]"
	@echo "     SEPOLIA_PCG_ENGINE_ADDRESS=[Fill this later]"
	@echo ""
	@echo "=================================================================="
	@echo "==============================AMOY================================"
	@echo ""
	@echo "     AMOY_RPC_URL=https://<your-amoy-api-key>"
	@echo "     AMOY_OKLINK_API_KEY=<your-amoy-oklink-api-key>"
	@echo "     AMOY_DEPLOYER_ADDRESS=[Add the address of the encrypted key for AMOY]"
	@echo "     AMOY_ACCOUNT=[AMOY-KEY-NAME]"
	@echo ""
	@echo "     AMOY_NATIVE_TO_USD_PRICEFEED_ADDRESS=0x001382149eBa3441043c1c66972b4772963f5D43"
	@echo "     AMOY_EUR_TO_USD_PRICEFEED_ADDRESS=0xa73B1C149CB4a0bf27e36dE347CBcfbe88F65DB2"
	@echo "     AMOY_VRF_WRAPPER_ADDRESS=0x6e6c366a1cd1F92ba87Fd6f96F743B0e6c967Bf0"
	@echo ""
	@echo "     AMOY_PCG_FACTORY_ADDRESS=[Fill this later]"
	@echo "     AMOY_PCG_ENGINE_ADDRESS=[Fill this later]"
	@echo ""
	@echo "=================================================================="
	@echo "============================GENERAL==============================="
	@echo "     WITH_GAS_REPORT=false"
	@echo "=================================================================="
	@echo "5. Run the tests by the command:"
	@echo "    make test-all"
	@echo "6. Type the following command to deploy PCG Factory and PCG Engine to Anvil"
	@echo "    make deploy NETWORK=anvil"
	@echo "7. From the new deployments folder find the addresses of PCG Factory and Engine"
	@echo "Only in Anvil deployment you should also find the VRFWrapper"
	@echo "   You can also find them from the terminal that anvil runs"
	@echo "8. Add them to the env file in"
	@echo "     ANVIL_PCG_FACTORY_ADDRESS=[---> HERE <---]"
	@echo "     ANVIL_PCG_ENGINE_ADDRESS=[---> HERE <---]"
	@echo "     ANVIL_VRF_WRAPPER_ADDRESS=[---> HERE <---]"
	@echo "9. To deploy a PCG Expansion type"
	@echo "     make deploy-expansion NETWORK=anvil CID=<your-cid> NOMC=<a-number-that-you-want>"
	@echo "To deploy on Sepolia or Amoy repeat the process and add NETWORK=sepolia/amoy accordingly instead of anvil"
	@echo "Retry the tests"


install-deps:
	foundry-rs/forge-std --no-commit
	forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 --no-commit
	forge install OpenZeppelin/openzeppelin-contracts@v5.0.2 --no-commit

