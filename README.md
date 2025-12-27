# Battery charge limiter service for Linux on x86-64
This application can be used primarily on OpenRC-based systems, whenever all other options fail to provide a reliable way to control or set the battery charge limit in a system in a persistent manner at startup.

I created it based on a need that was previously met by the 'bat-asus-battery' application and, later, by the system's own DE, both of which failed due to the dependency on systemd as the system's init.
This application is made using OpenRC as the service launcher, allowing configuration persistence during system boot, and also serving in application mode for quick in-session configuration, similar to what 'bat-asus-battery' does.

#### Installation
There is a provided tarball for quick setup under 'release' folder.
In a terminal at current repository folder (as super user):

```
 > tar -xvzf release/batt-ctl_openrc.tar.gz -C /
 > rc-update add batt-ctl-svc default
```

#### Usage
After that, the command `batt-ctl` and the `/etc/batt-ctl/searchpaths.conf` config file are available for the charge limit setup.
From now, you can reboot your system, and then see the log file at `/var/log/batt-ctl.log` to see the results.
The config file is self explanatory inside, and if it doesn't work to your hardware with the configurations provided, you may need to research a little to find a valid path for your current hardware and modify it as needed.

Application mode is started by the following command line:

```
 > sudo batt-ctl -ol NN%
```

Where 'NN' is the desired upper charge limit. The application will search and try to set it in all SEARCH entries within configuration file and report the result.

#### Uninstall
Just delete the service, remove the 3 files related to this application, plus the log file aforementioned (as super user):

```
 > rc-update del batt-ctl-svc
 > rm /usr/bin/batt-ctl
 > rm /etc/batt-ctl/searchpaths.conf
 > rm /etc/init.d/batt-ctl-svc
 > rm /var/log/batt-ctl.log
```

#### Note¹
For anyone who wants to compile it from source, the following are needed to be installed and properly set up:

 - [fasm2](https://github.com/tgrysztar/fasm2 "flat assembler 2")
 - [fastcall_v1](https://github.com/Jesse-6/fastcall_v1 "C-style fastcall macro toolkit for fasm2")

Service entry for OpenRC and config file are located in the tarball under release.

#### Note²
I welcome any feedback on solutions for other systems, aiming to improve this application's ability to adapt to as many systems as possible. This led me to create it as an interpreter for a configuration file.

Therefore, feel free to open an issue or even a pull request if you find something that improves its usefulness.
