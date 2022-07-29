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
   *  Deploy and Verify SingleAuction
   */
   {   
    const SingleAuction = await ethers.getContractFactory('SingleAuction', {
      signer: (await ethers.getSigners())[0]
    });
    const singleAuctionContract = await upgrades.deployProxy(SingleAuction, [feeAddress], { initializer: 'initialize' });
    await singleAuctionContract.deployed()

    console.log('SingleAuction proxy deployed: ', singleAuctionContract.address)

    singleAuctionImplementation = await upgrades.erc1967.getImplementationAddress(singleAuctionContract.address);
    console.log('SingleAuction Implementation address: ', singleAuctionImplementation)

    await sleep(60);
    // Verify SingleAuction
    try {
      await hre.run('verify:verify', {
        address: singleAuctionImplementation,
        constructorArguments: []
      })
      console.log('SingleAuction verified')
    } catch (error) {
      console.log('SingleAuction verification failed : ', error)
    }    
  }

  /**
   *  Deploy and Verify SingleFixed
   */
   {   
    const SingleFixed = await ethers.getContractFactory('SingleFixed', {
      signer: (await ethers.getSigners())[0]
    });
    const singleFixedContract = await upgrades.deployProxy(SingleFixed, [feeAddress], { initializer: 'initialize' });
    await singleFixedContract.deployed()

    console.log('SingleFixed proxy deployed: ', singleFixedContract.address)

    singleFixedImplementation = await upgrades.erc1967.getImplementationAddress(singleFixedContract.address);
    console.log('SingleFixed Implementation address: ', singleFixedImplementation)

    await sleep(60);
    // Verify SingleFixed
    try {
      await hre.run('verify:verify', {
        address: singleFixedImplementation,
        constructorArguments: []
      })
      console.log('SingleFixed verified')
    } catch (error) {
      console.log('SingleFixed verification failed : ', error)
    }
  }

  /**
   *  Deploy and Verify MultipleFixed
   */
  {   
    const MultipleFixed = await ethers.getContractFactory('MultipleFixed', {
      signer: (await ethers.getSigners())[0]
    });
    const multipleFixedContract = await upgrades.deployProxy(MultipleFixed, [feeAddress], { initializer: 'initialize' });
    await multipleFixedContract.deployed()

    console.log('MultipleFixed proxy deployed: ', multipleFixedContract.address)

    multipleFixedImplementation = await upgrades.erc1967.getImplementationAddress(multipleFixedContract.address);
    console.log('MultipleFixed Implementation address: ', multipleFixedImplementation)

    await sleep(60);
    // Verify MultipleFixed
    try {
      await hre.run('verify:verify', {
        address: multipleFixedImplementation,
        constructorArguments: []
      })
      console.log('MultipleFixed verified')
    } catch (error) {
      console.log('MultipleFixed verification failed : ', error)
    }   
  }

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
