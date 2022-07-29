require('dotenv').config()
const hre = require('hardhat')

const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay * 1000));

async function main() {
  const ethers = hre.ethers
  const upgrades = hre.upgrades;
  
  console.log('network:', await ethers.provider.getNetwork())

  const signer = (await ethers.getSigners())[0]
  console.log('signer:', await signer.getAddress())

  const factoryAddress = '0xbfdc82b243263a4177456a2225014e3948a9d80c';
  
  const NFTStakingFactory = await ethers.getContractFactory('NFTStakingFactory', {
    signer: (await ethers.getSigners())[0]
  });

  const nftStakingFactory = NFTStakingFactory.attach(factoryAddress);

  /**
   * Add Subscriptions
   */
  {
    const subscriptions = [
      {
        name: 'Basic',
        period: 2592000, // 1 months
        price: '1'
      },
      {
        name: 'Standard',
        period: 7776000, // 3 months
        price: '3'
      },
      {
        name: 'Premium',
        period: 15552000, // 6 months
        price: '5'
      }
    ]
    for (let index = 0; index < subscriptions.length; index++) {
      const subscription = subscriptions[index];
      const tx = await nftStakingFactory.addSubscription(subscription.name, subscription.period, ethers.utils.parseEther(subscription.price));
      await tx.wait();
      console.log('Add subscription : ', JSON.stringify(subscription));
    }    
  }

  /**
   * Add APR
   */
   {
    const aprs = [
      80, // 8 %
      120, // 12 %
      180, // 18 %
    ]
    for (let index = 0; index < aprs.length; index++) {
      const apr = aprs[index];
      const tx = await nftStakingFactory.addApr(apr);
      await tx.wait();
      console.log('Add apr : ', apr);
    }    
  }
  

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
