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

Talking to contractor
~~~~~~~~~~~~~~~~~~~~~

There are a few ways to work with the demo, here is the same sort of thing with each.

**curl**

The API is HTTP and JSON (called CInP).  It needs the ``Cinp-Version: 2.0`` header (older
examples may show a different version, they will get "Invalid CInP Protocol Version"),
and uses a few verbs curl is not used to: ``LIST``, ``GET``, ``CREATE`` and ``CALL``.  Log in,
the result is a token, which goes in the headers along with the user name::

  CHOST=http://localhost:8080
  CINP=( -s -H 'Cinp-Version: 2.0' -H 'Content-Type: application/json' )
  TOKEN=$(curl "${CINP[@]}" -X CALL -d '{"username":"root","password":"root"}' $CHOST/api/v1/Auth/User\(login\) | tr -d '"')
  CINP+=( -H "Auth-Id: root" -H "Auth-Token: $TOKEN" )

  curl "${CINP[@]}" -X CALL -d '{}' $CHOST/api/v1/Auth/User\(whoami\)

Look at the structures and one of the foundations::

  curl "${CINP[@]}" -X LIST -H 'Count: 20' -H 'Position: 0' $CHOST/api/v1/Building/Structure
  curl "${CINP[@]}" -X GET $CHOST/api/v1/Building/Structure:2:
  curl "${CINP[@]}" -X GET $CHOST/api/v1/Building/Foundation:test01:

Create a new Test foundation, give it an interface on the ``main`` network, and a structure
(the id of what is created is in the ``Object-Id`` header, use ``curl -i`` to see it)::

  curl -i "${CINP[@]}" -X CREATE -d '{"locator":"curl01","site":"/api/v1/Site/Site:site1:","blueprint":"/api/v1/BluePrint/FoundationBluePrint:test-foundation-base:"}' $CHOST/api/v1/Test/TestFoundation
  curl -i "${CINP[@]}" -X CREATE -d '{"foundation":"/api/v1/Building/Foundation:curl01:","name":"eth0","physical_location":"eth0","network":"/api/v1/Utilities/Network:1:","is_provisioning":true}' $CHOST/api/v1/Utilities/RealNetworkInterface
  curl -i "${CINP[@]}" -X CREATE -d '{"hostname":"curl01","site":"/api/v1/Site/Site:site1:","blueprint":"/api/v1/BluePrint/StructureBluePrint:test-structure-base:","foundation":"/api/v1/Building/Foundation:curl01:"}' $CHOST/api/v1/Building/Structure

Start a create job on a foundation (the result is the job id), and see where it is, then log out::

  curl "${CINP[@]}" -X CALL -d '{}' "$CHOST/api/v1/Building/Foundation:test01:(doCreate)"
  curl "${CINP[@]}" -X CALL -d '{}' "$CHOST/api/v1/Building/Foundation:test01:(getJob)"
  curl "${CINP[@]}" -X GET $CHOST/api/v1/Foreman/FoundationJob:1:
  curl "${CINP[@]}" -X CALL -d '{}' $CHOST/api/v1/Auth/User\(logout\)

NOTE: a foundation's create job does not start until the foundation is "located",
the job stays in the ``waiting`` state (``can_start`` is ``False``) until then.
Foundations get located when they belong to a built complex, or by a cartographer
(bare metal), there is no API call to do it by hand, so for the demo's standalone
Test and Manual foundations the jobs will wait.

See https://t3kton.github.io/contractor/api.html for everything the API can do.

**contractorcli**

``contractorcli`` is in the contractor container, and is already set up to talk to
contractor as ``root``, so there is nothing to install or configure::

  docker-compose exec contractor contractorcli structure list
  docker-compose exec contractor contractorcli foundation get test01
  docker-compose exec contractor contractorcli foundation test create -s site1 -l cli01 -b test-foundation-base
  docker-compose exec contractor contractorcli foundation job do-create test01
  docker-compose exec contractor contractorcli foundation joblog test01

If you will be using it a lot, an alias saves some typing, and ``shell`` gives you an
interactive prompt (it needs the terminal, so leave out the ``-T`` if you add one)::

  alias contractorcli='docker-compose exec contractor contractorcli'
  contractorcli shell

To run it from your own machine instead, download the binary from
https://github.com/T3kton/contractorcli/releases/latest (it is built for Linux, so on
macOS or Windows use the container), put it on your path, and create ``~/.contractorcli.ini``::

  [contractor]
  host: http://localhost:8080
  username: root
  password: root

See https://t3kton.github.io/contractor/contractorcli.html for the commands.

Kubernetes
~~~~~~~~~~

The third interface is the ``Structure`` custom resource from the kubernetes operator
(https://github.com/t3kton/kubernetes).  It is optional, start the demo with the
``kubernetes`` profile (``make src`` first if you have not built the image, the operator is
built from ``src/kubernetes``)::

  docker-compose --profile kubernetes up -d --build

That adds ``k3s``, a control plane only Kubernetes (API server and datastore, no nodes,
so it can not run pods and is nowhere near a real cluster), the ``operator``, and two
one time containers that exit when done: ``k8s-certs`` makes a self signed certificate for the
operator's webhooks (instead of cert-manager) and ``k8s-setup`` installs the CRD and the
webhook configuration (``k8s-webhooks.yaml``).  ``kubectl`` is in the k3s container, nothing
is needed on the host.  The operator logs in to contractor as ``root``.

The webhooks are on, so ``spec: {id: 2}`` is enough, the ``state`` and ``blueprint`` are filled
in from contractor, and the operator refuses changes contractor would not allow.  Adopt ``test01``
(the ``id`` is in ``contractorcli structure list``)::

  docker-compose exec -T k3s kubectl apply -f - << EOF
  apiVersion: contractor.t3kton.com/v1
  kind: Structure
  metadata:
    name: test01
  spec:
    id: 2
  EOF

  docker-compose exec k3s kubectl get structures -o wide

The webhooks need contractor to check against, so right after a ``up`` the first apply
can be refused with "unable to connect to contractor", wait for contractor to be healthy.

Setting ``state: built`` starts the ``create`` job in contractor, ``planned`` starts a ``destroy``,
the job shows up in ``kubectl get structures`` and in the contractor UI::

  docker-compose exec k3s kubectl patch structure test01 --type merge -p '{"spec":{"state":"built"}}'

While it is built, trying to change the ``blueprint`` or ``kubectl delete`` it is refused by
the validation webhook, set the state back to ``planned`` first.

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
