# CS:S-server-blacklist


This is my server blacklist file to block the giant cess pool of fake servers that started to appear is CS:S in 2023  

I will update as I notice my browser filling up again with trash.  

This scripted version is testing some automation of the process.  
blacklist-css-rbs-manual.txt  
whitelist-css-rbs-manual.txt  
These new files are the manual override files to filter with.  
Example listings in server_blacklist.txt  

```
	"server"
    {
        "name"        "ReduceBS 164.132.201.109 M #BS:1"
        "date"        "1728651914"
        "addr"        "164.132.201.109:0"
    }
    "server"
    {
        "name"        "ReduceBS 178.172.212.169 A #BS:33"
        "date"        "1728651914"
        "addr"        "178.172.212.169:0"
    }
A = Auto, M = Manual, #BS = detected server instances on this IP of BrowserSpam at the date listed
```

-BallGanda  

Guide from another user on steam with pictures. Use his guide with my updated file
https://steamcommunity.com/sharedfiles/filedetails/?id=3013281836  
  
or text instructions here...  
# Installation/import

Recommended method is to import this list into your game. This will add to any blacklisting you may have already done.  
Download the "server_blacklist.txt" file from here to a location you remember. Can delete the file after import  
Open CS:S  
Open the server browser  
Go to the "Blacklisted Servers" tab  
At the lower right click the button for "Import servers from file"  
Select the "server_blacklist.txt" file you downloaded and import it  
Done  
Can now delete the txt file you downloaded from here  

FYI:  
The "server_blacklist.txt file used/saved by CS:S lives in the CS:S games cfg folder found on windows installs at "Program Files (x86)\Steam\steamapps\common\Counter-Strike Source\cstrike\cfg"

