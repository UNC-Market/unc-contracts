require('dotenv').config()
const hre = require('hardhat')

const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay * 1000));

async function main() {
  const ethers = hre.ethers
  const upgrades = hre.upgrades;

  console.log('network:', await ethers.provider.getNetwork())

  const signer = (await ethers.getSigners())[0]
  console.log('signer:', await signer.getAddress())

  const deployFlag = {
    verifyFactory: false,
    verifyMerchant: false,
    deployMerchantTemplate: false,
    cloneMerchant: true,
    deployFactory: false,
    upgradeFactory: false,
  };

  /**
   * Verify Merchant
   */
  if (deployFlag.verifyMerchant) {
    const merchantAddress = '0x8c878d705de10B7a31C82922aFD870BC4f7d2b66';

    await hre.run('verify:verify', {
      address: merchantAddress,
      constructorArguments: []
    })

    console.log("Merchant at: ", merchantAddress, " verified");
  }

  /**
   * Verify SlashFactory
   */
  if (deployFlag.verifyFactory) {
    const implementationAddress = '0x0d4c9de53ec60fa97328bc1de94814975ea3b03f' // SlashFactory implementation contract address
    await hre.run('verify:verify', {
      address: implementationAddress,
      constructorArguments: []
    })
    console.log('SlashFactory Implementation contract verified')
  }

  /**
   * Deploy Merchant Template
   */
  if (deployFlag.deployMerchantTemplate) {
    const Merchant = await ethers.getContractFactory('Merchant', { signer: (await ethers.getSigners())[0] })

    const merchantContract = await Merchant.deploy();
    await merchantContract.deployed();
    await sleep(30);
    console.log("Merchant template deployed to: ", merchantContract.address);
  }

  /**
   *  Deploy SlashFactory
   */
  if (deployFlag.deployFactory) {
    const commonOwner = '0x172A25d57dA59AB86792FB8cED103ad871CBEf34';
    const merchantTemplate = '0x8c878d705de10B7a31C82922aFD870BC4f7d2b66';
    const defaultController = '0x8c4ac09b2Fd85d8Dff274a26D9b8ece2D84210d8';

    const SlashFactory = await ethers.getContractFactory('SlashFactory', {
      signer: (await ethers.getSigners())[0]
    });
    const factoryContract = await upgrades.deployProxy(SlashFactory, [commonOwner, merchantTemplate, defaultController], { initializer: 'initialize' });
    await factoryContract.deployed()

    console.log('SlashFactory proxy deployed: ', factoryContract.address)
  }

  /**
   * Upgrade SlashFactory
   */
  if (deployFlag.upgradeFactory) {
    const factoryAddress = "0x052314b94D8609F1F60674e239E783d0B2bFD0dC";

    const SlashFactoryV2 = await ethers.getContractFactory('SlashFactory', {
      signer: (await ethers.getSigners())[0]
    })

    const upgradedFactoryContract = await upgrades.upgradeProxy(factoryAddress, SlashFactoryV2);
    console.log('SlashFactory upgraded: ', upgradedFactoryContract.address)
  }

  /**
   * Clone Merchant from SlashFactory
   */
  if (deployFlag.cloneMerchant) {
    const factoryAddress = '0x052314b94D8609F1F60674e239E783d0B2bFD0dC';
    const merchantWallet = '0x7861e0f3b46e7C4Eac4c2fA3c603570d58bd1d97';
    const receiveToken = '0x0000000000000000000000000000000000000000';
    const reserved = [];

    const SlashFactory = await ethers.getContractFactory('SlashFactory', { signer: (await ethers.getSigners())[0] });
    const slashFactory = await SlashFactory.attach(factoryAddress);

    const tx = await slashFactory.deployMerchant(merchantWallet, receiveToken, reserved);
    await tx.wait();
    console.log('Merchant Cloned');
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
