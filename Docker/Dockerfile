# Builds the managed StatsDirect engine and stages the macOS .NET runtime it
# needs, so a Mac only requires Xcode command line tools and Python 3.
#
# Nothing macOS-specific is compiled here: Swift, the C++ dylibs and codesign
# still run on the host. See docker-build.sh.
FROM mcr.microsoft.com/dotnet/sdk:10.0

# curl ships in the image; the installer fetches the macOS runtime at build time.
RUN curl --fail --silent --show-error --location https://dot.net/v1/dotnet-install.sh -o /usr/local/bin/dotnet-install.sh \
 && chmod 0755 /usr/local/bin/dotnet-install.sh

ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_GENERATE_ASPNET_CERTIFICATE=false \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

COPY engine-publish.sh /usr/local/bin/engine-publish.sh
RUN chmod 0755 /usr/local/bin/engine-publish.sh

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/engine-publish.sh"]
