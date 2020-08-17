# check-certs.sh
forked from cgmartin/check-certs.sh

## Why
This project exists to solve the problem of monitoring SSL-certificate expiry dates and to send alerts when a certificate is due for renewal, with the added support for multiple alert methods & datasources.

## Requirements
Tested on Debian with the following packages:
* netcat
* mysql-client
* curl
* sendEmail
* openssl

## Features to be added
* Support for multiple datasources for domains
* Silent mode
* Getopts for running against single domains
* Additional error handling to ensure the script delivers accurate data
