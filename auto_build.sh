#!/bin/bash
#----------------------------------------------------------------------
# ganesha 编译打包脚本，实现ganesha自动编译打包
#----------------------------------------------------------------------
#
set -e
cd `dirname $0`

MODULE="ganesha"
AUTHOR="bear"
PREFIX="/opt/bear"	# 安装路径

DIR_WORK=$(pwd)
DIR_BASE=${DIR_WORK}
DIR_PACKAGE="package"
DIR_BUILD="build"
DIR_SCRIPT="scripts"
FILE_INSTALL="install_${MODULE}.sh"	# 安装脚本
FILE_INFO="info.txt"			# 包信息描述文件
FILE_UTILS="utils.sh"			# 通用函数定义文件
PACKAGE_DATA="data.tar.bz2"		# 程序包

# -- include --
. /usr/local/utils.sh "build"	# "package.log"

# get version
VERSION="5.0"
# get os type
OS=$(GET_OS_TYPE)
# get arch type
ARCH=$(GET_ARCH)
# get package name
PACKAGE="${MODULE}_${VERSION}.${OS}.${ARCH}.tar.bz2"	# 安装包

# -- Basic Info --
echo ""
PRINT "----------------------------------------"
PBLUE "module: ${MODULE}"
PRINT "version: ${VERSION}"
PRINT "author: ${AUTHOR}"
PRINT "package: ${PACKAGE}"
PRINT "install prefix: ${PREFIX}"
PRINT "----------------------------------------"

# -- Make Clean --
if [ "$1" = "clean" ]; then
	PRINT "make clean..."

	rm -rf ${DIR_BUILD}
	rm -rf ${DIR_PACKAGE}
	if [ -d "ganesha_service" ]; then
		rm -rf ganesha_service
	fi
	if [ -d "ganesha_dbus" ]; then
		rm -rf ganesha_dbus
	fi
	if [ -d "ganesha_depends" ]; then
		rm -rf ganesha_depends
	fi
	set +x
	PSUCCESS "make clean done."
	exit 0;
fi

# -- Prepare to Make --
mkdir ${DIR_WORK} -p
mkdir ${DIR_PACKAGE} -p
rm -rf ${DIR_PACKAGE}/*
mkdir ${DIR_BUILD}/${MODULE} -p

# -- Configure & Make & Make install --
cd ${DIR_BUILD}
if [ "$1" = "asan" ]; then
	cmake -DSANITIZE_ADDRESS=ON ../src
else
	cmake ../src
fi

PRINT "cmake done."

make -j 32 PREFIX=${PREFIX}
PINFO "make done."

make install DESTDIR=${DIR_BASE}/${DIR_BUILD}/${MODULE} PREFIX=""
PINFO "make install done."

# -- Prepare to Pack --
# Pack ganesha .so file
cd ${DIR_BASE}

find ${DIR_BUILD}
mkdir ${DIR_BUILD}/lib -p
uname_r=`uname -r`
processor_type=`uname -p`
# check if it is EulerOS
set +e
os_type=$(GET_OS_TYPE /ets/os-release "ID")
os_type=${os_type,,}
os_type=`echo ${os_type//\"/}`
os_ver=$(GET_CONF_ITEM /etc/os-release "VERSION_ID")
os_ver=`echo $os_ver//\"/}`

# TODO: copy the rely tools, such as rpcbind, rpc.statd, sm-notify

# Pack ganesha service
GANESHA_SERVICE="ganesha_service"
mkdir -p ${GANESHA_SERVICE}
cp -p ${DIR_BASE}/src/scripts/init.d/nfs-ganesha.euler ${GANESHA_SERVICE}/ganesha

touch ${GANESHA_SERVICE}/ganesha.nfsd.pid
cp -p ${DIR_BASE}/src/scripts/systemd/ganesha.service ${GANESHA_SERVICE}

# Pack ganesha dbus service
GANESHA_DBUS="ganesha_dbus"
mkdir -p ${GANESHA_DBUS}
GANESHA_DBUS_DEPEND="/usr/lib/python3.10/site-packages"
cp -r -p ./src/scripts/ganeshactl ${GANESHA_DBUS}
cp -r -p ${GANESHA_DBUS_DEPEND}/pyparsing ${GANESHA_DBUS}
cp -r -p ${GANESHA_DBUS_DEPEND}/pyparsing-3.0.7.dist-info ${GANESHA_DBUS}

mkdir -p ${DIR_BUILD}${PREFIX}
mv ${GANESHA_DBUS} ${DIR_BUILD}${PREFIX}
mv ${DIR_BUILD}/lib ${DIR_BUILD}${PREFIX}
mv ${DIR_BUILD}/${MODULE} ${DIR_BUILD}${PREFIX}
mv ${GANESHA_SERVICE} ${DIR_BUILD}${PREFIX}

# -- Make data-package --
cd ${DIR_BASE}/${DIR_PACKAGE}
PRINT "start to make data package..."
tar -jcf ${PACKAGE_DATA} -C ../${DIR_BUILD}${PREFIX} . # ./bin ./lib ./sbin ./etc ./libexec
ret=$?
if [ "$ret" == "0" ]; then
	PRINT "make package succeed."
else
	PERROR "make package failed! status code = $ret"
	exit 1
fi

# -- Record Info --
echo "module=${MODULE}" > ${FILE_INFO}
echo "version=${VERSION}" >> ${FILE_INFO}
echo "md5=$(MD5_CALC ${PACKAGE_DATA} )" >> ${FILE_INFO}
echo "build_date="$(date +"%Y-%m-%d %H:%M:%S") >> ${FILE_INFO}

# -- Make product package --
PRINT "start to make product package..."
mkdir -p ${MODULE}
chmod 755 ${DIR_BASE}/scripts/*.sh
cp -p ${DIR_BASE}/scripts/${FILE_INSTALL} ./
cp -r ${DIR_BASE}/scripts/uninstall_ganesha.sh ./
mv uninstall_ganesha.sh ${MODULE}
cp -r ${PACKAGE_DATA} ${FILE_INFO} ${FILE_INSTALL} ${MODULE}

tar -jcvf ${PACKAGE} ${MODULE}
ret=$?
if [ "$ret" == "0" ]; then
	PRINT "pack package succeed."
else
	PERROR "pack package failed! status code = $ret"
	exit 1
fi

# --Clean tmp file --
rm -rf ${MODULE}
cd ..

# -- Complete --
PSUCCESS "${MODULE} build succeed, package is '${DIR_PACKAGE}/${PACKAGE}'."
