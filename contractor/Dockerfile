FROM ubuntu:bionic as build

RUN apt update; \
apt upgrade; \
apt install -y software-properties-common; \
add-apt-repository -y ppa:pnhowe/t3kton; \
DEBIAN_FRONTEND=noninteractive apt install -y git build-essential respkg nodejs npm debhelper python3-dev python3-setuptools wget liblzma-dev

RUN git clone https://github.com/T3kton/contractor.git; \
git clone https://github.com/T3kton/contractor_plugins.git; \
git clone https://github.com/T3kton/resources.git

RUN cd contractor ;\
cd ui && npm install ;\
sed s/"export Ripple from '.\/ripple';"/"export { default as Ripple } from '.\/ripple';"/ -i node_modules/react-toolbox/components/index.js ;\
sed s/"export Tooltip from '.\/tooltip';"/"export { default as Tooltip } from '.\/tooltip';"/ -i node_modules/react-toolbox/components/index.js

RUN for i in contractor_plugins resources; do cd $i && make -j2 respkg && mv *.respkg .. && cd ..; done;
RUN for i in contractor contractor_plugins; do cd $i && make dpkg && cd ..; done


FROM ubuntu:bionic as release

RUN apt update; \
apt upgrade; \
apt install -y software-properties-common; \
add-apt-repository -y ppa:pnhowe/t3kton; \
DEBIAN_FRONTEND=noninteractive apt install -y tzdata respkg python3-django python3-jinja2 python3-parsimonious python3-pip apache2 bind9 bind9utils libapache2-mod-wsgi-py3 python3-cinp python3-psycopg2 python3-pymongo python3-werkzeug python3-toml python3-pip postgresql-client postgresql-10 mongodb-server iproute2; \
ln -fs /usr/share/zoneinfo/UTC /etc/localtime; \
dpkg-reconfigure --frontend noninteractive tzdata; \
pip3 install toml --upgrade

COPY --from=build *.deb /
COPY --from=build *.respkg /

RUN /etc/init.d/postgresql start; \
/etc/init.d/mongodb start; \
ln -s /bin/true /bin/systemctl; \
/bin/bash -c "dpkg -i *.deb"; \
su postgres -c "echo \"CREATE ROLE contractor WITH PASSWORD 'contractor' NOSUPERUSER NOCREATEDB NOCREATEROLE LOGIN;\" | psql"; \
su postgres -c "createdb -O contractor contractor"; \
a2dissite 000-default; \
/usr/lib/contractor/util/manage.py migrate; \
/bin/bash -c "respkg -i contractor-plugins-iputils_*.respkg"; \
/bin/bash -c "respkg -i contractor-os-base_*.respkg"; \
/bin/bash -c "respkg -i contractor-ubuntu-base_*.respkg"; \
/bin/bash -c "respkg -i contractor-centos-base_*.respkg"; \
/bin/bash -c "respkg -i contractor-plugins-manual_*.respkg"; \
/usr/lib/contractor/setup/setupWizard --no-ip-reservation --dns-server=10.0.0.10 --ntp-server=contractor --primary-interface=eth0 --root-password=root; \
/etc/init.d/postgresql stop; \
kill $(cat /var/run/mongodb/mongodb.pid)

COPY start.sh /

CMD ./start.sh

EXPOSE 80/tcp
