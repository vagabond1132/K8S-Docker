# --------------------------------------------------
#
# Dockerfile to build HighGoDB container images
# Base on neokylin 7.4 x86-64
# --------------------------------------------------

# Set the base image to neokylin

FROM hgdb-sec-neokylin-v4:raw



ENV LANG en_US.utf8
RUN mkdir /docker-entrypoint-initdb.d

ADD create-database.sh /docker-entrypoint-initdb.d
ADD oa20190416pm.backup /docker-entrypoint-initdb.d

ADD highgodb-4.3.4-1.ns7.mips64el.rpm /opt
ADD pwfile  /opt
#ADD pgpass /opt
ADD recovery.conf  /opt
ADD hg_repmgr.conf /opt

ENV PATH /opt/HighGoDB-4.3.4/bin:$PATH
ENV PGDATA /opt/HighGoDB-4.3.4/data
ENV LD_LIBRARY_PATH /opt/HighGoDB-4.3.4/lib
ENV HG_BASE /opt/HighGoDB-4.3.4

RUN echo "export PATH=\$PATH:/opt/HighGoDB-4.3.4/bin" >> ~/.bashrc
RUN echo "export LD_LIBRARY_PATH=/opt/HighGoDB-4.3.4/lib" >> ~/.bashrc && source ~/.bashrc

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh /

EXPOSE  5866
ENTRYPOINT ["/bin/bash", "-c", "docker-entrypoint.sh && tailf /var/log/messages" ]
