
require("stream")
require("terminal")
require("filesys")
require("strutil")
require("process")
require("terminal")


Settings={}
Settings.iso_list={}
Settings.programs={}



function FindFiles(pattern_list)
local toks, pattern, glob, item
local files={}

toks=strutil.TOKENIZER(pattern_list, ",")
pattern=toks:next()
while pattern ~= nil
do
	glob=filesys.GLOB(pattern)
	if glob:size() > 0
	then
		item=glob:next()
		while item ~= nil
		do
			table.insert(files, item)
			item=glob:next()
		end
	end
pattern=toks:next()
end

return files
end


-- find an item matching a pattern within a mounted iso image.
-- Patterns are fnmatch style 'glob' patterns. 
-- Multiple patterns can be supplied, separated by commas
-- The first matching item is returned. It's path is RELATIVE to the iso mount point
function ISOFindItem(pattern, mount_point)
local i, item, files
local result=""

toks=strutil.TOKENIZER(pattern, ",")
item=toks:next()
while item ~= nil
do
	files=FindFiles(mount_point..item)
	if #files ==0 then files=FindFiles(mount_point.."*/"..item) end

	if #files > 0 
	then 
		result=string.sub(files[1], strutil.strlen(mount_point)) 
		break
	end

item=toks:next()
end

return result
end


function LoadDistroParseLine(line)
local toks, str
local iso_details={}

iso_details.install_type=""
toks=strutil.TOKENIZER(line, "\\S", "Q")
str=toks:next()
while str ~= nil
do
	if string.sub(str, 1, 5)=="name=" then iso_details.name=strutil.stripQuotes(string.sub(str, 6)) end
	if string.sub(str, 1, 13)=="install_type=" then iso_details.install_type=strutil.stripQuotes(string.sub(str, 14)) end
	if string.sub(str, 1, 3)=="id=" then iso_details.pattern=strutil.stripQuotes(string.sub(str, 4)) end
	if string.sub(str, 1, 7)=="kernel=" then iso_details.kernel=strutil.stripQuotes(string.sub(str, 8)) end
	if string.sub(str, 1, 7)=="initrd=" then iso_details.initrd=strutil.stripQuotes(string.sub(str, 8)) end
	if string.sub(str, 1, 7)=="append=" then iso_details.append=strutil.stripQuotes(string.sub(str, 8)) end
	if string.sub(str, 1, 12)=="append-live=" 
	then 
		iso_details.install_type="live"
		iso_details.append_live=strutil.stripQuotes(string.sub(str, 13)) 
	end
	str=toks:next()
end

return iso_details
end


function LoadDistroList()
local S, str, iso_details
local toks

toks=strutil.TOKENIZER(Settings.distro_file, ":")
path=toks:next()

while path ~= nil
do

S=stream.STREAM(path, "r")
if S ~= nil
then
	str=S:readln()
	while str~= nil
	do
		str=strutil.trim(str)
		if strutil.strlen(str) > 0 and string.sub(str, 1, 1) ~= '#'
		then
		iso_details=LoadDistroParseLine(str)
		table.insert(Settings.iso_list, iso_details)
		end
		str=S:readln()
	end

	S:close()
	break
end

path=toks:next()
end

end


-- a list of file patterns that exist for a given ISO/distro
function ISOFindIDFiles(distro, patterns)
local toks, pattern

toks=strutil.TOKENIZER(patterns, ",")
pattern=toks:next()
while pattern ~= nil
do
	files=FindFiles(distro.mnt..pattern)
	if #files == 0 then return false end
	pattern=toks:next()
end

return true
end


function CategorizeISO(distro)
local files, i, details

for i,details in ipairs(Settings.iso_list)
do
	if ISOFindIDFiles(distro, details.pattern) == true
	then 
		distro.name=details.name
		distro.install_type=details.install_type
		if strutil.strlen(details.kernel) > 0 then distro.kernel=ISOFindItem(details.kernel, distro.mnt) end
		if strutil.strlen(details.initrd) > 0 then distro.initrd=ISOFindItem(details.initrd, distro.mnt) end
		distro.append=details.append
		break
	end
end

end



function AnalyzeISO(path)
local mnt
local files={}
local distro={}
local kernel_names="vmlinuz*,bzImage,kernel*"
local initrd_names="initrd*,initfs*,initrfs*,initramfs*"

distro.name="generic"
distro.kernel=""
distro.initrd=""
distro.root_files={}

mnt="/tmp/.iso_"..process.getpid()
filesys.mkdir(mnt)

os.execute(Settings.programs["mount"] .. " -oloop,ro '"..path.."' '"..mnt.."'")

distro.mnt=mnt.."/"
CategorizeISO(distro)

if distro.kernel == "" then distro.kernel=ISOFindItem(kernel_names, distro.mnt) end
if distro.initrd == "" then distro.initrd=ISOFindItem(initrd_names, distro.mnt) end

Out:puts("~c"..filesys.basename(path).."~0  DISTRO: ~e"..distro.name.."~0  kernel="..distro.kernel.."  initrd="..distro.initrd.."\n")
return distro
end



function CleanUpISO(distro)
os.execute("umount "..distro.mnt)
filesys.rmdir(distro.mnt)
end



function CheckDevRemovable(devname)
local S, str, path
local removable=false

path="/sys/block/"..devname
S=stream.STREAM(path.."/removable", "r")
if S ~= nil
then
	str=strutil.trim(S:readln())
	if str=="1" 
	then 
		removable=true
	end
end

return removable
end


function CheckDevMounted(devname)
local S, str, toks, mount, devpath
local mounted=false

S=stream.STREAM("/proc/mounts", "r")
if S ~= nil
then
	str=S:readln()
	while str ~= nil
	do
		str=strutil.trim(str)
		toks=strutil.TOKENIZER(str, "\\S")

		devpath="/dev/"..devname
		mount=toks:next()
		if string.sub(mount, 1, strutil.strlen(devpath)) == devpath
		then
			mounted=true
			break
		end
		str=S:readln()
	end
	S:close()
end

return mounted
end


-- look up various information about a device (disk or partition) from the /sys file system
-- information includes whether the device is removable, and whether it's mounted
function DeviceInfoFromSys(dev)
local name, path, glob
local devtype=""
local devname=""
local diskname=""
local removable=false
local mounted=false

devname=filesys.basename(dev)
if string.sub(dev, 1, 5) ~= '/dev/' then return "directory", false end

path="/sys/block/"..devname
if filesys.exists(path) == true
then
  devtype="disk"
	diskname=devname
else
  glob=filesys.GLOB("/sys/block/*/"..devname)
  str=glob:next()
  if strutil.strlen(str) > 0
  then
    diskname=filesys.dirname(str)
    devtype="partition"
  end
end


if strutil.strlen(devtype) > 0
then
	removable=CheckDevRemovable(diskname)
	mounted=CheckDevMounted(devname) 
end

return diskname, devname, devtype, removable, mounted
end


function PartitionUUID(partition)
local S, str, toks, tok

S=stream.STREAM("cmd:"..Settings.programs["blkid"].. " "..partition)
if S ~= nil
then
	str=S:readln()
	S:close()
	toks=strutil.TOKENIZER(str, " ")
	tok=toks:next()
	while tok ~= nil
	do
	if string.sub(tok, 1, 5) == "UUID="
	then
		str=strutil.stripQuotes(string.sub(tok, 6))
		return str
	end
	tok=toks:next()
	end
end

	
return ""
end

function SetupDest()
local devname, devtype, removable, mounted
local from, to

	--diskname is the name of the parent disk for a destination. For disk destinations devname and diskname will
	--be the same. For partitions, for example /dev/sda1,  devname=sda1 and diskname=sda
	diskname,devname,devtype,removable,mounted=DeviceInfoFromSys(Settings.InstallDest)

	if devtype == ""
	then
		Out:puts("~rERROR:~0 "..Settings.InstallDest.." cannot find device!\n")
		Out:reset()
		os.exit()
	end

	if removable ~= true and Settings.Force ~=true
	then
		Out:puts("~rERROR:~0 "..Settings.InstallDest.." is not a removable device!\n")
		Out:reset()
		os.exit()
	end

	if mounted == true
	then
		Out:puts("~rERROR:~0 "..Settings.InstallDest.." (or partitions within it) is mounted!\n")
		Out:reset()
		os.exit()
	end

	if devtype=="disk"
	then
		if Settings.programs["sfdisk"] ~= nil
		then
			os.execute("echo ';;b;*;;' | "..Settings.programs["sfdisk"].." -f "..Settings.InstallDest)
		elseif Settings.programs["parted"] ~= nil
		then
			os.execute(Settings.programs["parted"] .. " "..Settings.InstallDest.." --script -- mkpart primary fat32 0% 100%")
			os.execute(Settings.programs["parted"] .. " "..Settings.InstallDest.." --script -- set 1 boot on")
		end
		Settings.InstallDest=Settings.InstallDest.."1"
		Settings.Format=true
	end


	from=Settings.SyslinuxDir .."/".. Settings.SyslinuxMBR
	to="/dev/"..diskname
	print("install mbr: ".. from.. " to "..to)
	filesys.copy(from, to) 

	Settings.tmpMount=("/tmp/.usb_install_"..tostring(process.pid()))
	filesys.mkdir(Settings.tmpMount)
	Settings.MountPoint=Settings.tmpMount

	if Settings.Format==true
	then
	str=Settings.programs["mkfs.fat"] .. " -F 32 "..Settings.InstallDest
	print("Format Partition using: ".. str)
	os.execute(str)
	end

	-- must do this here, in case we reformatted the disk. Every new filesystem has a new uuid.
	Settings.DestUUID=PartitionUUID(Settings.InstallDest)

	if filesys.mount(Settings.InstallDest, Settings.MountPoint, "vfat") ==true
	then
		print("mounted: "..Settings.InstallDest.." on "..Settings.MountPoint )
	else
		print("mount failed: "..Settings.InstallDest.." on "..Settings.MountPoint )
	end

end


function InstallAddSyslinuxEntry(S, name, distro)

if distro.install_type=="live" then name=name.."-LIVE" end

S:writeln("LABEL "..name.."\n")
S:writeln("MENU LABEL "..name.."\n")
if strutil.strlen(distro.kernel) > 0 then S:writeln("KERNEL ".."/"..name..distro.kernel.."\n") end
if strutil.strlen(distro.initrd) > 0 then S:writeln("INITRD ".."/"..name..distro.initrd.."\n") end

if distro.install_type=="live"
then
	str=string.gsub(distro.append_live, "%$%(distdir%)", name)
	str=string.gsub(str, "%$%(uuid%)", Settings.DestUUID)
	S:writeln("APPEND "..str.."\n")
elseif strutil.strlen(distro.append) > 0
then
	str=string.gsub(distro.append, "%$%(distdir%)", name)

	if distro.install_type=="iso" then str=string.gsub(str, "%$%(isoname%)", name..".iso") end
	str=string.gsub(str, "%$%(uuid%)", Settings.DestUUID)
	S:writeln("APPEND "..str.."\n")
end

S:writeln("\n")
end


function InstallISO(S, iso_path, distro)
local name, dest

		name=string.gsub(filesys.basename(iso_path), ".iso$", "")

		dest=Settings.MountPoint.."/"..name.."/"
		filesys.mkdir(dest)

		if distro.install_type=="iso"
		then
		filesys.mkdirPath(dest..distro.kernel)
		filesys.copy(distro.mnt..distro.kernel, dest..distro.kernel)

		filesys.mkdirPath(dest..distro.initrd)
		filesys.copy(distro.mnt..distro.initrd, dest..distro.initrd)

		filesys.copy(iso_path, dest..name..".iso")
		else
		filesys.copydir(distro.mnt, dest)
		end

		InstallAddSyslinuxEntry(S, name, distro, "")
		if strutil.strlen(distro.append_live) > 0 then InstallAddSyslinuxEntry(S, name, distro, "live") end
end


function SyslinuxConfigOpen()
local S, path

path=Settings.MountPoint.."/syslinux.cfg"
if filesys.exists(path) == true
then
	S=stream.STREAM(Settings.MountPoint.."/syslinux.cfg","a")
else
	S=stream.STREAM(Settings.MountPoint.."/syslinux.cfg","w")
	if S ~= nil
	then
		S:writeln("DEFAULT menu.c32\n");
		S:writeln("PROMPT 0\n\n");
	end
end

return S
end


function InstallOSItems()
local S, toks, item, name,distro

S=SyslinuxConfigOpen()
if S~= nil
then
	toks=strutil.TOKENIZER(Settings.InstallItems, ",")
	item=toks:next()
	while item ~= nil
	do
		--if anything has gone wrong with parsing the install items we might get a blank item.
		--we don't want to try processing that so check the length
		if strutil.strlen(item) > 0
		then
		if filesys.exists(item)
		then
			distro=AnalyzeISO(item)
			if strutil.strlen(distro.kernel) > 0
			then
				InstallISO(S, item, distro)
			else
				Out:puts("~rERROR:~0 failed to find kernel to boot\n")
			end
		CleanUpISO(distro)
		else
			Out:puts("~rERROR:~0 no such install image '"..item.."'\n")
		end
		end
		item=toks:next()
	end

	S:close()
end
end



function InstallSyslinux()
local toks, item, str

filesys.mkdir(Settings.MountPoint.."/boot")
print("mkdir: "..Settings.MountPoint.."/boot")
toks=strutil.TOKENIZER(Settings.SyslinuxModules, ",")
item=toks:next()
while item ~= nil
do
print("Install Syslinux: "..item)
filesys.copy(Settings.SyslinuxDir.."/"..item, Settings.MountPoint.."/boot/"..item)
item=toks:next()
end
end


function ActivateSyslinux()
print("Activate syslinux")
str=Settings.programs["syslinux"] .. " --install -d /boot "..Settings.InstallDest
os.execute(str)
print("Activated: "..str)
end


function InitConfig()
local str

Settings.Version="3.1"
Settings.MountPoint="/mnt"
str=string.gsub(process.getenv("PATH"), "/bin", "/share")
Settings.SyslinuxDir=filesys.find("syslinux", str)
Settings.SyslinuxMBR="mbr.bin"
Settings.SyslinuxModules="ldlinux.c32,memdisk,libutil.c32,menu.c32"
Settings.InstallItems=""
Settings.Force=false
Settings.distro_file=process.getenv("HOME").."/.config/distroflash.conf"
Settings.distro_file=Settings.distro_file .. ":"..process.getenv("HOME").."/.distroflash.conf"
Settings.distro_file=Settings.distro_file .. ":" .. "/etc/distroflash.conf"
end



function CleanUp()

filesys.unmount(Settings.MountPoint)
if strutil.strlen(Settings.tmpMount) > 0 then filesys.rmdir(Settings.tmpMount) end
end



function DisplayVersion()

print("distroflash.lua. version: "..Settings.Version)
print("")

Out:reset()
os.exit(0)
end



function DisplayHelp()

print("distroflash.lua. version: "..Settings.Version)
print("")
print("usage:  lua distroflash.lua -d <dest> [options] <iso files>")
print("")
print("-d <device>       destination device to install to. Can be either a partition (e.g. /dev/sda1), or a drive (e.g. /dev/sda)")
print("-dev <device>     destination device to install to. Can be either a partition, or a drive")
print("-device <device>  destination device to install to. Can be either a partition, or a drive")
print("-c <path>         path to distroflash.conf config file, overriding default search path. Multiple paths can be supplied, seperated by ':'. The default is '~/.config/distroflash.conf:~/.distroflash.conf:/etc/distroflash.conf'")
print("-force            if distroflash objects that a device is not removable (not all devices set this flag) this option forces using the device")
print("-format           by default distroflash.lua will not format a partition (it will if you give it a drive). This option forces format.")
print("-syslinuxdir      path to syslinux dir containing mbr.bin, ldlinux.c32, etc. distroflash.lua should find this itself.")
print("-V                display version")
print("-version          display version")
print("--version         display version")
print("-?                this help")
print("-h                this help")
print("-help             this help")
print("--help            this help")
print("")
print("If you supply a disk as the destination device, distroflash.lua will PARTITION AND REFORMAT THE WHOLE DISK WIPING ANY DATA. If you supply a partition distroflash will not format it, and if a syslinux.cfg file already exists on that partition it will just add entries to the end of that file. If you want to format a partition and install from clean, you can use the '-format' option.")
print("")
print("EXAMPLES:")
print("")
print("   lua distroflash.lua -d /dev/sdc bodhi-5.0.0-64.iso linuxmint-19.3-xfce-32bit.iso  kali-linux-2020.1-live-i386.iso") 
print("")
print("The above line will WIPE drive /dev/sdc, partition it and create a fat32 file system, and install a multiboot menu for bodhi linux, mint, and kali linux")
print("")
print("   lua distroflash.lua -d /dev/sdc1 bodhi-5.0.0-64.iso linuxmint-19.3-xfce-32bit.iso  kali-linux-2020.1-live-i386.iso") 
print("")
print("The above line will install a multiboot menu for bodhi linux, mint, and kali linux, adding them to any existing syslinux.cfg or creating a new one")
print("")
print("   lua distroflash.lua -d /dev/sdc1 -format bodhi-5.0.0-64.iso linuxmint-19.3-xfce-32bit.iso  kali-linux-2020.1-live-i386.iso") 
print("")
print("The above line will WIPE and reformat partitions /dev/sdc1, and install a multiboot menu for bodhi linux, mint, and kali linux")


Out:reset()
os.exit(0)
end



function ParseCommandLine(args)
local i, arg

for i,arg in ipairs(args)
do
	if arg=="-d" or arg=="-dev" or arg=="-device"
	then
		Settings.InstallDest=args[i+1]
		args[i+1]=""
	elseif arg=="-c" or arg=="-config"
	then
		Settings.distro_file=args[i+1]				
		args[i+1]=""
	elseif arg=="-force"
	then
		Settings.Force=true				
	elseif arg=="-format"
	then
		Settings.Format=true
	elseif arg=="-syslinuxdir"
	then
		Settings.SyslinuxDir=args[i+1]				
		args[i+1]=""
	elseif arg=="-h" or arg=="-?" or arg=="-help" or arg=="--help"
	then
		DisplayHelp()
		elseif arg=="-V" or arg=="-version" or arg=="--version"
	then
		DisplayVersion()
	else
		Settings.InstallItems=Settings.InstallItems..arg..","
	end
end

end


-- Find a required program. For situations where more than one program can do the same job,
-- the programs can be seperated by a ',' and searched for
function FindRequiredProgram(prog)
local found=false
local toks, item

toks=strutil.TOKENIZER(prog, ",")
item=toks:next()
while item ~=nil
do
	str=filesys.find(item, process.getenv("PATH")..":/sbin:/usr/sbin:/usr/local/sbin")
	if strutil.strlen(str) > 0 
	then 
	Settings.programs[item]=str 
	found=true
	break
	end
	item=toks:next()
end

return found
end



function FindRequiredPrograms(progs)
local toks, prog
local result=true

toks=strutil.TOKENIZER(progs, " ")
prog=toks:next()
while prog ~= nil
do
	if FindRequiredProgram(prog) == true
	then
		Out:puts("~gFOUND:~0 "..str.."\n")
	else
		Out:puts("~rMISSING:~0 "..prog.."\n")
		result=false
	end
prog=toks:next()
end

return result
end




Out=terminal.TERM()
InitConfig()
ParseCommandLine(arg)
LoadDistroList()

if process.uid() ~= 0
then
	Out:puts("~rERROR:~0 You are not root. This program needs to be run with root permissions.\n")
elseif strutil.strlen(Settings.InstallDest) == 0
then
	Out:puts("~rERROR:~0 no install destination given. Please supply either a disk, a partition or a mounted directory using the '-d' option.\n")
elseif FindRequiredPrograms("mount umount syslinux mkfs.fat,mkfs.msdos sfdisk,parted") ~= true
then
	Out:puts("~rERROR:~0 some required programs are missing. Please install them or add the directories they are installed in to your $PATH.\n")
else

	if FindRequiredPrograms("modprobe") == true
	then
		os.execute(Settings.programs["modprobe"] .. " loop")
	else
	Out:puts("~yWARNING:~0 Can't find the 'modprobe' program. Make sure the module for loopback filesystems ('modprobe loop') is loaded.\n")
	end

	if FindRequiredPrograms("blkid") ~= true
	then
	Out:puts("~yWARNING:~0 Can't find the 'blkid' program. Some distros (TinyCore,Arch,Calculate,CentOS,NST,SystemRescueCD) may not work.\n")
	end

	if tonumber(process.lu_get("LibUseful:Version")) < 4.32
	then
	Out:puts("~yWARNING:~0 You are using a libUseful older than 4.32. Some distros (CentOS 8) may not work.\n");
	end

	devtype,removable=DeviceInfoFromSys(Settings.InstallDest)

	SetupDest()
	InstallOSItems()
	InstallSyslinux()
	CleanUp()
	ActivateSyslinux()
end

Out:reset()
