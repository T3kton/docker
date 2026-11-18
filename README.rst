Docker Files
============

Two ways to run contractor, both from the same image:

* the **demo**: contractor, a subcontractor with no DHCP, postgres and mongo,
  with the ``manual``, ``test`` and ``iputils`` plugins.  For looking at the UI
  and playing with the API, runs anywhere docker does.  The ``test`` plugin only
  simulates things, it does not provision anything.
* the **full** install: the same pieces a contractor VM has (UI/API, static
  files, caching proxy, DNS, TFTP) plus subcontractor and the DHCP server, so
  machines can be PXE booted and built.  Linux only.

NOTE: the passwords for the databases and the built in users (``bootstrap``,
``jobsig``, ``subcontractor``) are the defaults.  For more information see
https://t3kton.github.io/contractor/tryit/installing.html

Demo
----

::

  docker-compose up -d       # or "docker compose up -d"

then goto http://localhost:8080/ and log in as ``root`` with the password ``root``.
Set ``ROOT_PASSWORD`` and ``CONTRACTOR_PORT`` in the environment to change those.
The API is at http://localhost:8080/api/v1/, see https://t3kton.github.io/contractor/api.html

The first start takes a bit while the database is set up.  ``docker-compose down -v``
removes everything, including the database.

The ``demo-data`` service runs once when contractor is up (and shows as exited, that
is normal) and adds some things to look at: foundations ``test01`` - ``test04`` and
``manual01`` - ``manual04``, each with a structure, one interface on the ``main``
network and an address, at offsets 40-43 for the test ones and 50-53 for the manual
ones.  Nothing is built, use the UI or ``contractorcli`` (it is in the image, ie:
``docker-compose exec contractor contractorcli ...``, see ``load_demo_data`` for the
config it needs) to start jobs on them.  Running it again skips what is already there.

Full
----

The containers use the host's network (``network_mode: host``), the host acts as
the contractor VM does in the install docs: it needs to be on the network
machines will be built on, and that network must not already have a DHCP server.
These ports are used on the host: 53, 67/udp, 69/udp, 80, 3128, and 5432 and 27017
on 127.0.0.1.

::

  cp full.env.example full.env      # set LISTEN_INTERFACE and ROOT_PASSWORD, at least
  docker-compose -f docker-compose.full.yml --env-file full.env up -d

What runs:

* ``contractor``: the UI/API, the ``static`` site, the caching proxy on 3128, bind
  (DNS, for ``site1.test``, ``static``, ``proxy`` ...) and tftpd.  The first start
  runs ``setupWizard`` with the address of ``LISTEN_INTERFACE``, the same as the
  install docs, and loads the ``manual``, ``iputils``, ``ubuntu-base`` and iPXE respkgs.
* ``subcontractor``: runs the modules in ``SUBCONTRACTOR_MODULES``, default
  ``manual,iputils``, ie: ``manual,iputils,virtualbox:2`` (``:2`` is the limit).
* ``dhcpd``: the DHCP server, serves ``LISTEN_INTERFACE`` and points machines
  at this host for TFTP.

To use other plugins set ``CONTRACTOR_PLUGINS`` (the respkgs, ie: ``virtualbox``)
and add the module to ``SUBCONTRACTOR_MODULES``.  Plugins that need credentials
(vcenter, proxmox, ...) are configured with a complete ``subcontractor.conf``,
put it in ``./config`` (or ``SUBCONTRACTOR_CONFIG_DIR``) and it is used instead of
the generated one, see ``/etc/subcontractor.conf.sample`` in the image.

The addresses and the dynamic pool are not set up by default, same as the install
docs.  Set ``IP_RESERVATION=1`` if you want setupWizard to reserve offsets 2-20
and use 21-29 as the dynamic pool.

**IPMI/AMT:** the bootstrap/disk-wipe PXE images from ``disks`` are 1.5GB and can
not be built during ``docker build``.  Build them (see the install docs), put
``disks-contractor_*.respkg`` and ``disks-linux-installer-profiles_*.respkg`` in
``./respkgs`` (or ``RESPKG_DIR``) and they are installed at the next start of
``contractor``.  Any respkg in that directory is.

State is in docker volumes: the database, the bind config, the static/PXE files,
and the tftp files.  The contractor container can be recreated (ie: for a new
image) without losing anything, ``docker-compose down`` (without ``-v``) keeps it.

Build
-----

The image installs contractor and subcontractor from the t3kton PPA.  The respkgs
are not published anywhere, so they are built from source, and that needs to be
staged first (see the Makefile).  The first build also compiles iPXE, which takes
a while::

  make image                # clones the sources from github
  make image LOCAL=1        # uses the checkouts next to this one, with any uncommitted changes (respkgs only)

The one image is contractor, subcontractor and dhcpd, the first argument picks which.
See the top of ``entrypoint.sh`` for the environment variables.

Other plugins in the demo
-------------------------

The respkgs for all the plugins are in the image, to add one to the demo (ie: ipmi),
set ``CONTRACTOR_PLUGINS`` for the contractor service in the compose file, and add the
module to ``SUBCONTRACTOR_MODULES`` for the subcontractor service.
