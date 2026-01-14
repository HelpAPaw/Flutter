#!/bin/bash

# This script copies the appropriate GoogleService-Info.plist file based on the build configuration

SOURCE_DIR="${SRCROOT}/Runner"

if [ "${CONFIGURATION}" == "Debug" ]; then
    cp "${SOURCE_DIR}/GoogleService-Info-Debug.plist" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"
    echo "Using GoogleService-Info-Debug.plist for Debug configuration"
elif [ "${CONFIGURATION}" == "Release" ] || [ "${CONFIGURATION}" == "Profile" ]; then
    cp "${SOURCE_DIR}/GoogleService-Info-Release.plist" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"
    echo "Using GoogleService-Info-Release.plist for ${CONFIGURATION} configuration"
else
    echo "Warning: Unknown configuration ${CONFIGURATION}. Using Release configuration."
    cp "${SOURCE_DIR}/GoogleService-Info-Release.plist" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"
fi
