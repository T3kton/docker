# One image for everything, the role is picked by the first argument to the
# entrypoint (contractor, subcontractor or dhcpd), see entrypoint.sh.
#
# contractor, subcontractor and the plugins are the packages from the t3kton
# PPA.  The respkgs (blueprints and PXE resources) are not published anywhere
# yet, so they are built here from the sources staged in src/ (see the
# Makefile), except for the ones from disks, see the README.

FROM ubuntu:noble AS respkg-build

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common ca-certificates git wget make fakeroot build-essential liblzma-dev perl && \
    add-apt-repository -y ppa:pnhowe/t3kton && \
    apt-get install -y --no-install-recommends respkg

# os-base, ubuntu-base (installer kernel/initrd), utility and the iPXE boot
# loaders, this is the slow one (iPXE is compiled) and changes the least, so it
# is first
COPY src/resources /src/resources

RUN mkdir /respkgs && \
    make -C /src/resources respkg && \
    mv /src/resources/*.respkg /respkgs

# the plugin respkgs, they are small, the ones not enabled by default can be
# installed later with "respkg -i"
COPY src/contractor_plugins /src/contractor_plugins

RUN make -C /src/contractor_plugins respkg && \
    mv /src/contractor_plugins/*.respkg /respkgs


FROM ubuntu:noble

ENV DEBIAN_FRONTEND=noninteractive

# no init system in the container, the package scripts want systemctl and
# to start services, so stub them for the install and remove the stub after,
# the divert is so the stub survives systemd being installed as a dependency
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d && \
    dpkg-divert --local --add --rename --divert /usr/bin/systemctl.real /usr/bin/systemctl && \
    printf '#!/bin/sh\nexit 0\n' > /usr/bin/systemctl && chmod +x /usr/bin/systemctl && \
    apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common ca-certificates curl tzdata && \
    add-apt-repository -y ppa:pnhowe/t3kton && \
    apt-get install -y --no-install-recommends contractor contractor-plugins subcontractor subcontractor-plugins respkg bind9 iproute2 cron tftpd-hpa python3-pysnmp4 python3-pyasyncore && \
    /usr/lib/contractor/setup/apache_setup --no-proxy && \
    apt-get purge -y software-properties-common && apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/* /usr/bin/systemctl && \
    dpkg-divert --local --remove --rename /usr/bin/systemctl && \
    printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/systemctl && chmod +x /usr/local/bin/systemctl

# systemctl is left as a no-op in /usr/local/bin, apache_setup calls it and
# apache is started by the entrypoint

COPY --from=respkg-build /respkgs /usr/share/contractor-respkgs
COPY entrypoint.sh /entrypoint.sh

VOLUME /var/lib/contractor
EXPOSE 80/tcp

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "contractor" ]
