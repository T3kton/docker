Docker Files
============

To build a docker container of contractor, checkout this repo.  Then
run::

  cd contractor
  docker build . -t contractor

To run the container run::

  docker run -p80 contractor
