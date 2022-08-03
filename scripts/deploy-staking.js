require('dotenv').config()
const hre = require('hardhat')

const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay * 1000));

async function main() {
  const ethers = hre.ethers
  const upgrades = hre.upgrades;

  console.log('network:', await ethers.provider.getNetwork())

  const signer = (await ethers.getSigners())[0]
  console.log('signer:', await signer.getAddress())

  const feeAddress = process.env.FEE_ADDRESS;


  /**
  *  Deploy and Verify SingleNFTStakingFactory
  */
  {
    const SingleNFTStakingFactory = await ethers.getContractFactory('SingleNFTStakingFactory', {
      signer: (await ethers.getSigners())[0]
    });
    const singleNFTStakingFactoryContract = await upgrades.deployProxy(SingleNFTStakingFactory, [feeAddress], { initializer: 'initialize' });
    await singleNFTStakingFactoryContract.deployed()

    console.log('SingleNFTStakingFactory proxy deployed: ', singleNFTStakingFactoryContract.address)

    singleNFTStakingFactoryImplementation = await upgrades.erc1967.getImplementationAddress(singleNFTStakingFactoryContract.address);
    console.log('SingleNFTStakingFactory Implementation address: ', singleNFTStakingFactoryImplementation)

    await sleep(60);
    // Verify SingleNFTStakingFactory
    try {
      await hre.run('verify:verify', {
        address: singleNFTStakingFactoryImplementation,
        constructorArguments: []
      })
      console.log('SingleNFTStakingFactory verified')
    } catch (error) {
      console.log('SingleNFTStakingFactory verification failed : ', error)
    }
  }

  /**
  *  Deploy and Verify MultiNFTStakingFactory
  */
   {
    const MultiNFTStakingFactory = await ethers.getContractFactory('MultiNFTStakingFactory', {
      signer: (await ethers.getSigners())[0]
    });
    const multiNFTStakingFactoryContract = await upgrades.deployProxy(MultiNFTStakingFactory, [feeAddress], { initializer: 'initialize' });
    await multiNFTStakingFactoryContract.deployed()

    console.log('MultiNFTStakingFactory proxy deployed: ', multiNFTStakingFactoryContract.address)

    multiNFTStakingFactoryImplementation = await upgrades.erc1967.getImplementationAddress(multiNFTStakingFactoryContract.address);
    console.log('MultiNFTStakingFactory Implementation address: ', multiNFTStakingFactoryImplementation)

    await sleep(60);
    // Verify MultiNFTStakingFactory
    try {
      await hre.run('verify:verify', {
        address: multiNFTStakingFactoryImplementation,
        constructorArguments: []
      })
      console.log('MultiNFTStakingFactory verified')
    } catch (error) {
      console.log('MultiNFTStakingFactory verification failed : ', error)
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
