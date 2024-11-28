#!/bin/bash
# Copyright (c) 2020 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#


#########################################
# Generate Che CA and server certificates
#########################################

# Should be provided as environment variable.
# Examples:
#   che.domain.net
#   192.168.99.100.nip.io
DOMAIN=${DOMAIN}
if  [ -z "$DOMAIN" ]; then
    echo 'Error: "DOMAIN" environment variable is not set'
    exit 1
fi
DNS_ENTRIES=DNS:$(echo ${DOMAIN} | sed  's|,|,DNS:|g')
CHE_CA_CN='Local Eclipse Che Signer'
CHE_CA_KEY_FILE='ca.key'
CHE_CA_CERT_FILE='ca.crt'

ECLIPSE_CHE_SERVER='Eclipse Che Server'
CHE_SERVER_ORG='Local Eclipse Che'
CHE_SERVER_KEY_FILE='domain.key'
CHE_SERVER_CERT_REQUEST_FILE='domain.csr'
CHE_SERVER_CERT_FILE='domain.crt'

# Figure out openssl configuration file location
OPENSSL_CNF='/etc/pki/tls/openssl.cnf'
if [ ! -f $OPENSSL_CNF ]; then
    OPENSSL_CNF='/etc/ssl/openssl.cnf'
fi

# Change directory to writable one
cd $HOME

# Generate private key for Che root CA
# Options:
#  -out : name of file to write generated key to
#  4096 : number of bits in the key
openssl genrsa -out $CHE_CA_KEY_FILE 4096

# Generate Che root CA certificate and sign it with previously generated key.
# Options:
#  -batch : script (non-interactive) mode
#  -new : creates new sertificate request
#  -x509 : produces self signed sertificate instead of certificate request
#  -nodes : no DES, do not encrypt private key
#  -key : private key to use to sign this certificate
#  -sha256 : hash to use
#  -subj : subject name. Should contain at least distinguished (common) name (CN). Format: /type0=value0/type1=value1
#  -days : number of days this certificate will be valid for
#  -reqexts : specifies extension to be included
#  -extensions : adds extensions (with its configuration)
#  -config : openssl config file to use
#  -outform : format of the certificate container
#  -out : name of file to write generated certificate to
openssl req -batch -new -x509 -nodes -key $CHE_CA_KEY_FILE -sha256 \
            -subj /CN="${CHE_CA_CN}" \
            -days 1024 \
            -reqexts SAN -extensions SAN \
            -config <(cat ${OPENSSL_CNF} <(printf '[SAN]\nbasicConstraints=critical, CA:TRUE\nkeyUsage=keyCertSign, cRLSign, digitalSignature')) \
            -outform PEM -out $CHE_CA_CERT_FILE

# Generate Che server prvate key.
# Options:
#  -out : name of file to write generated key to
#  2048 : number of bits in the key
openssl genrsa -out $CHE_SERVER_KEY_FILE 2048

# Create certificate request for the Che server domain.
# Options:
#  -batch : script (non-interactive) mode
#  -new : creates new sertificate request
#  -sha256 : hash to use
#  -key : private key to use to sign this certificate request
#  -subj : subject name, defines some information about future certificate
#  -reqexts : specifies extension to be included
#  -config : openssl config file to use
#  -outform : format of the certificate container
#  -out : name of file to write generated certificate to
openssl req --batch -new -sha256 -key $CHE_SERVER_KEY_FILE \
            -subj "/O=${CHE_SERVER_ORG}/CN=${ECLIPSE_CHE_SERVER}" \
            -reqexts SAN \
            -config <(cat $OPENSSL_CNF <(printf "\n[SAN]\nsubjectAltName=${DNS_ENTRIES}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth")) \
            -outform PEM -out $CHE_SERVER_CERT_REQUEST_FILE

# Create certificate for the Che server domain based on given certificate request.
# Options:
#  -req : process certificate request instead of certificate
#  -in : specifies file with certificate request to process
#  -CA : CA certificate which should be used for signing the certificate request
#  -CAkey : specifies CA private key to sign the certificate request with
#  -CAcreateserial : generate and include certificate serial number
#  -sha256 : hash to use
#  -days : number of days this certificate will be valid for
#  -extfile : config file which contains certificate extensions which should be included in the resulting certificate
#  -outform : format of the certificate container
#  -out : name of file to write generated certificate to
openssl x509 -req -in $CHE_SERVER_CERT_REQUEST_FILE -CA $CHE_CA_CERT_FILE -CAkey $CHE_CA_KEY_FILE -CAcreateserial \
             -days 365 \
             -sha256 \
             -extfile <(printf "subjectAltName=${DNS_ENTRIES}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth") \
             -outform PEM -out $CHE_SERVER_CERT_FILE

# Check that required files have been created
if ! [[ -f $CHE_CA_CERT_FILE && -f $CHE_SERVER_KEY_FILE && -f $CHE_SERVER_CERT_FILE ]]; then
    echo 'Error during certificates generation phase. Check logs above.'
    exit 10
fi

#Log that all certificates are created
echo 'Che TLS certificates are created.'


############################################
# Create secrets from generated certificates
############################################

# It is supposed that the Che namespace is already exists

CHE_NAMESPACE="${CHE_NAMESPACE:-che}"
CHE_SERVER_TLS_SECRET_NAME="${CHE_SERVER_TLS_SECRET_NAME:-che-tls}"
CHE_CA_CERTIFICATE_SECRET_NAME="${CHE_CA_CERTIFICATE_SECRET_NAME:-self-signed-certificate}"

# Create Che server TLS secret for trafic encryption. Private.
kubectl create secret tls $CHE_SERVER_TLS_SECRET_NAME --key=$CHE_SERVER_KEY_FILE --cert=$CHE_SERVER_CERT_FILE --namespace=$CHE_NAMESPACE
if [ $? -ne 0 ]; then
    echo "Error while creating TLS secret \"${CHE_SERVER_TLS_SECRET_NAME}\"."
    exit 20
fi

# Create Che certificate authority secret. Public. Should be shared with users and imported in browser.
kubectl create secret generic $CHE_CA_CERTIFICATE_SECRET_NAME --from-file=$CHE_CA_CERT_FILE --namespace=$CHE_NAMESPACE
if [ $? -ne 0 ]; then
    echo "Error while creating secret \"${CHE_CA_CERTIFICATE_SECRET_NAME}\"."
    exit 21
fi

# Label the resulting secrets.
# It is used to have the secret cached in the operator client.
if [ -n "$LABELS" ]; then
    kubectl label secret "${CHE_SERVER_TLS_SECRET_NAME}" ${LABELS} --namespace=$CHE_NAMESPACE
    if [ $? -ne 0 ]; then
        echo "Error while labeling secret \"${CHE_SERVER_TLS_SECRET_NAME}\"."
        exit 22
    fi

    kubectl label secret "${CHE_CA_CERTIFICATE_SECRET_NAME}" ${LABELS} --namespace=$CHE_NAMESPACE
    if [ $? -ne 0 ]; then
        echo "Error while labeling secret \"${CHE_CA_CERTIFICATE_SECRET_NAME}\"."
        exit 23
    fi
fi

# Log that everything is done
echo 'Che TLS secrets are created.'
