#!/bin/bash

#
# This script creates a fips compliant vault store to hold masked passwords.
# Initially, the vault contains a public/private key pair that's used to
# mask/unmask the administrative key.  The admin key in turn is used to
# AES encrypt the various vaulted items.
#

function abort {
  echo "Aborting vault initialization!"
  echo
  exit 1
}

function read_answer {
    read ANSWER
    ANSWER="${ANSWER}x"
    ANSWER=${ANSWER:0:1}
}

echo
echo "Please enter the full path to the NSS database directory.  If this"
echo "directory does not exist, you will be asked to allow the script to"
echo "create it."
echo
echo -n "Enter the full path: "
read DBDIR

BOOL_ISNEWDB=false
if [ ! -d $DBDIR ]
then
    echo
    echo "The directory '$DBDIR' does not exist."
    echo -n "Do you want to create it? <Y/n> "
    read_answer

    if [ $ANSWER = "N" -o "$ANSWER" = "n" ]
    then
        abort
    else
        BOOL_ISNEWDB=true
    fi
fi

mkdir -p $DBDIR || abort

# make sure we have a full path
pushd $DBDIR 2>&1 > /dev/null
DBDIR=`pwd`
popd 2>&1 > /dev/null

echo
echo "The directory '$DBDIR' will be used to hold the vault data."
echo -n "Is this correct? <Y/n> "
read_answer

if [ $ANSWER = "N" -o $ANSWER = "n" ]
then
    abort
fi

if [ $BOOL_ISNEWDB = false ]
then
    echo
    echo "The directory '$DBDIR' already exists and may contain valid vault files."
    echo -n "Do you want to delete those files and create a new vault? <y/N> "
    read_answer

    if [ $ANSWER = "Y" -o $ANSWER = "y" ]
    then
        rm -fr $DBDIR/*
        BOOL_ISNEWDB=true
    else
        echo
        echo "The existing vault files were not changed."
        echo
    fi
fi

PROG_ARGS=
if [ $BOOL_ISNEWDB = true ]
then
    echo
    echo "Creating the NSS database files for the vault ..."
    modutil -force -create -dbdir ${DBDIR} || abort
    echo $?
    chmod a+r ${DBDIR}/*.db

    echo
    echo "Setting fips mode to true for the NSS database ..."
    modutil -force -fips true -dbdir ${DBDIR} || abort

    echo
    echo "Setting the NSS token PIN.  The PIN is a FIPS compliant password which"
    echo "must be at least seven characters in length and include characters from"
    echo "at least three of the following character classes:"
    echo
    echo "    1) ASCII digits"
    echo "    2) lowercase ASCII"
    echo "    3) uppercase ASCII"
    echo "    4) non-alphanumeric ASCII"
    echo "    5) non-ASCII"
    echo
    echo "If an ASCII uppercase letter is the first character of the password/PIN,"
    echo "the uppercase letter is not counted toward its character class. Similarly,"
    echo "if a digit is the last character of the password/PIN, the digit is not"
    echo "counted toward its character class."
    echo
    modutil -force -changepw "NSS FIPS 140-2 Certificate DB" -dbdir ${DBDIR} || abort

    echo
    echo "Adding a random public/private key pair to the NSS database.  You will be"
    echo "prompted to enter the same token PIN as the previous step."

    # The cert fields don't matter since we only need the public/private key pair.
    # Also, these keys won't expire for 100 years with the real intention that the
    # user rekeys the vault long before that by running this script and resetting
    # the public/private key pair and all of the vaulted passwords.
    certutil -S -k rsa -g 2048 -n vaultcert -t "u,u,u" -v 1197 -x \
        -s "CN=localhost, OU=MYOU, O=MYORG, L=MYCITY, ST=MYSTATE, C=US" -d ${DBDIR} || abort

    echo
    echo "The vault store has been successfully initialized and individual masked"
    echo "passwords can now be added."
    echo

    PROG_ARGS="--new-vault"
fi

# Setup JBOSS_HOME
DIRNAME="`dirname $0`"
RESOLVED_JBOSS_HOME=`cd $DIRNAME/..; pwd`
if [ "x$JBOSS_HOME" = "x" ]; then
    # get the full path (without any relative bits)
    JBOSS_HOME=$RESOLVED_JBOSS_HOME
else
    SANITIZED_JBOSS_HOME=`cd "$JBOSS_HOME"; pwd`
    if [ "$RESOLVED_JBOSS_HOME" != "$SANITIZED_JBOSS_HOME" ]; then
        echo "WARNING JBOSS_HOME may be pointing to a different installation - unpredictable results may occur."
        echo
    fi
fi
export JBOSS_HOME

# Setup the JVM
if [ "x$JAVA" = "x" ]; then
    if [ "x$JAVA_HOME" != "x" ]; then
        JAVA="$JAVA_HOME/bin/java"
    else
        JAVA="java"
    fi
fi

if [ "x$JBOSS_MODULEPATH" = "x" ]; then
    JBOSS_MODULEPATH="$JBOSS_HOME/modules"
fi

JAVA_OPTS="$JAVA_OPTS -Dfips.vault.path=$DBDIR"

# Display our environment
echo "========================================================================="
echo ""
echo "  JBoss FIPS-Compliant Vault"
echo ""
echo "  JBOSS_HOME: $JBOSS_HOME"
echo ""
echo "  JAVA: $JAVA"
echo "  JAVA_OPTS: $JAVA_OPTS"
echo ""
echo "========================================================================="
echo ""

$JAVA $JAVA_OPTS -jar $JBOSS_HOME/jboss-modules.jar \
         -mp ${JBOSS_MODULEPATH} org.jboss.security.fips.plugins \
         $PROG_ARGS
