This file explains the organization of the World Wind Subversion repository's directories, and briefly outlines their contents.

WorldWind
=========
The 'WorldWind' folder contains the World Wind Java SDK project. Many resources are available at http://goworldwind.org to help you understand and use World Wind. Key files and folders in the World Wind Java SDK:
* build.xml: Apache ANT build file for the World Wind Java SDK.
* src: Contains all Java source files for the World Wind Java SDK, except the World Wind WMS Server.
* server: Contains the World Wind WMS Server Java source files, build file, and deployment files.
* lib-external/gdal: Contains the GDAL native binaries libraries that may optionally be distributed with World Wind.

WWAndroid
=========
the 'WWAndroid' folder contains the World Wind Android SDK project. Many resource are available at http://goworldwind.org/android to help you understand and use World Wind on Android. Key files and folders in the World Wind Android SDK:
* build.xml: Apache ANT build file for the World Wind Android SDK.
* src: Contains all Java source files for the World Wind Android SDK.
* examples: Contains example applications that use the World Wind Android SDK.

GDAL
====
The 'GDAL' folder contains the GDAL native library project. This project produces the GDAL native libraries used by the World Wind Java SDK (see WorldWind/lib-external/gdal). The GDAL native library project contains detailed instructions for building the GDAL native libraries on the three supported platforms: Linux, Mac OS X, and Windows.
