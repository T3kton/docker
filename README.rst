Docker Files
============

NOTE: the docker container version of contractor does not include an
instance of subcontractor, nor is it fully configured for supplying
static files for some types of deployments.  This is really intended
for developing/testing against the API and/or looking into contractor.
For more information see: https://t3kton.github.io/contractor/Docker.html


Build
-----

To build a docker container of contractor, checkout this repo.  Then
run::

  cd contractor
  docker build . -t contractor

To run the container run::

  docker run -p80 contractor
