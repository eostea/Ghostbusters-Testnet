# Quick Instructions for Returning User

[中文版本](https://github.com/HKEOS/Ghostbusters-Testnet/blob/master/returning-user_CN.md)

Between launches, we will typically update a significant portion of the scripts. 

This is a quick guide on how to get ready for the next launch as soon as possible.

**Note:** Skip parts that you know that are unnecessary for your scenario (for example, if you have already updated EOS.IO to the next tag, skip the "Update EOS" part)

### Update EOS
```console
Follow the updated part in the beginning of the Readme.md file.
```

### Ghostbusters folder

First, `cd` into the Ghostbusters folder.

```console
curl -sL https://raw.githubusercontent.com/HKEOS/Ghostbusters-Testnet/master/setup.sh | bash -
```
This updates all of your scripts but `params.sh`

```console
rm params.sh
wget https://raw.githubusercontent.com/HKEOS/Ghostbusters-Testnet/master/params.sh
nano params.sh
# Fill in your information again
# Save
cat my-peer-info
# Check that your peer info is still correct
```

### ghostbusters-<account-name> folder

```console
sudo rm -r ghostbusters-<account-name>
./installGhostbusters.sh
./publishPeerInfo.sh my-peer-info
./updatePeers
```

By completing these, you should have your node peered and ready to go again!

Wait until the team decides on a launch block before you run `autolaunch.sh`. Run `updatePeers.sh` regularly to add new members into the mesh.
