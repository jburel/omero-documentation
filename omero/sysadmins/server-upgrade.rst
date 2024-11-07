OMERO.server upgrade
====================

The OME team is committed to providing frequent, project-wide upgrades both
with bug fixes and new functionality. We try to make the schedule for these
releases as public as possible. You may want to take a look at the `GitHub Projects
<https://github.com/orgs/ome/projects>`_ for exactly what will
go into a release. See also :doc:`omeroweb-upgrade`.

See the full details of OMERO |version_openmicroscopy| features in the :doc:`/users/history`.

This guide aims to be as definitive as possible so please do not be put off by
the level of detail; upgrading should be a straightforward process.

.. warning::

    If you are upgrading from a version *prior to* OMERO
    |previousversion| then you *must* also study the upgrade
    instructions for those prior versions because they may describe
    important steps that these instructions assume to already have been
    done by OMERO |previousversion| users. Before proceeding with these
    instructions you may first need to read the `instructions
    <https://docs.openmicroscopy.org/latest/omero5.5/sysadmins/server-upgrade.html>`_
    for upgrading *to* OMERO |previousversion| because some extra steps
    may be required beyond simply running the SQL upgrade scripts
    described below.


Upgrade checklist
-----------------

.. contents::
    :local:
    :depth: 1

Check prerequisites
^^^^^^^^^^^^^^^^^^^

Before starting the upgrade, please ensure that you have reviewed and
satisfied all the :doc:`system requirements <system-requirements>` with
:doc:`correct versions <version-requirements>` for installation. In
particular, ensure that you are running a suitable version of PostgreSQL
to enable successful upgrading of the database, otherwise the upgrade
script aborts with a message saying that your database server version is
less than the OMERO prerequisite.

File limits
^^^^^^^^^^^

You may wish to review the open file limits. Please consult the
:ref:`limitations-openfiles` section for further details.

Password usage
^^^^^^^^^^^^^^

The passwords and logins used here are examples. Please consult the
:ref:`troubleshooting-password` section for explanation. In particular, be
sure to replace the values of **db_user** and **omero_database** with the
actual database user and database name for your installation.

Memoization files invalidation
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

All cached Bio-Formats memoization files created at import time will be
invalidated by the server upgrade. This means the very first loading of each
image after upgrade will be slower. After re-initialization, a new memoization
file will be automatically generated and OMERO will be able to load images in
a performant manner again.

These files are stored under :file:`BioFormatsCache` in the OMERO data
directory, e.g. :file:`/OMERO/BioFormatsCache`. You may see error messages in
your log files when an old memoization file is found; to avoid these messages
delete everything under this directory before starting the upgraded server.

It is possible to regenerate the memoization files before the user loads an image 
for the first time. For more information, read 
`MemoFileRegenerationReadMe.md <https://github.com/glencoesoftware/omero-ms-image-region/tree/v0.5.1/src/dist/MemoFileRegenerationReadMe.md>`_.  

Troubleshooting
^^^^^^^^^^^^^^^

If you encounter errors during an OMERO upgrade, database upgrade, etc., you
should retain as much log information as possible and notify the OMERO.server
team via the `forum <https://www.openmicroscopy.org/forums>`_.

Upgrade check
^^^^^^^^^^^^^

All OMERO products check themselves with the OmeroRegistry for update
notifications on startup. If you wish to disable this functionality you should
do so now as outlined on the :doc:`UpgradeCheck` page.

Upgrade steps
-------------

For all users, the basic workflow for upgrading your OMERO.server is listed
below. Please refer to each section for additional details.

.. contents::
    :local:
    :depth: 1

Check ahead for upgrade issues
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

There is a ``precheck`` SQL script provided that performs various database
checks to verify readiness for upgrade. The precheck script works even
with the OMERO server running so it may be used before downtime for the
actual upgrade is scheduled. Issues that the script reports will need to
be resolved before the upgrade may proceed. The precheck script will
**not** make any changes to the database: it merely performs various
precautionary checks also done by the actual upgrade script.

.. parsed-literal::

    $ cd OMERO.server
    $ psql -h localhost -U **db_user** **omero_database** < sql/psql/|current_dbver|/|previous_dbver|-precheck.sql
    Password for user **db_user**:
    ...
    ...
                               status
    ---------------------------------------------------------------------
                                                                        +
                                                                        +
                                                                        +
    YOUR DATABASE IS READY FOR UPGRADE TO VERSION |current_dbver|       +
                                                                        +
                                                                        +

    (1 row)


.. warning::

   The :file:`sql/psql/OMERO5.4__0/OMERO5.3__1-precheck.sql` script
   referenced by the above :program:`psql` command assumes a planned
   upgrade from OMERO 5.3.4. If you are instead currently running OMERO
   5.3.3 or an earlier 5.3.x version then you perform the precheck by
   using the above command with
   :file:`sql/psql/OMERO5.4__0/OMERO5.3__0-precheck.sql`. That script
   verifies that the database contains no trace of
   :secvuln:`2017-SV5-filename-2` having been exploited; this
   vulnerability was fixed in OMERO 5.3.4.

.. _back-up-the-db:

Perform a database backup
^^^^^^^^^^^^^^^^^^^^^^^^^

The first thing to do before **any** upgrade activity is to backup your
database.

.. parsed-literal::

    $ pg_dump -h localhost -U **db_user** -Fc -f before_upgrade.db.dump **omero_database**


Copy new binaries
^^^^^^^^^^^^^^^^^

Before copying the new binaries, stop the existing server::

    $ cd OMERO.server
    $ omero admin stop

Your OMERO configuration is stored using :file:`config.xml` in the
:file:`etc/grid` directory under your OMERO.server directory. Assuming you
have not made any file changes within your OMERO.server distribution
directory, you are safe to follow the following upgrade procedure:

.. parsed-literal::

    $ cd ..
    $ mv OMERO.server OMERO.server-old
    $ unzip OMERO.server-|version_openmicroscopy|-ice36.zip
    $ ln -s OMERO.server-|version_openmicroscopy|-ice36 OMERO.server
    $ cp OMERO.server-old/etc/grid/config.xml OMERO.server/etc/grid

.. _upgradedb:

Upgrade your database
^^^^^^^^^^^^^^^^^^^^^

.. warning::
    This section only concerns users upgrading from a 5.3 or
    earlier server. If upgrading from a 5.4 or 5.5 server, you do not need
    to upgrade the database.

Ensure Unicode character encoding
"""""""""""""""""""""""""""""""""

OMERO requires a Unicode-encoded database; without it, the upgrade
script aborts with a message warning how the ``OMERO database character
encoding must be UTF8``. From :command:`psql`::

  # SELECT datname, pg_encoding_to_char(encoding) FROM pg_database;
    datname   | pg_encoding_to_char
  ------------+---------------------
   template1  | UTF8
   template0  | UTF8
   postgres   | UTF8
   omero      | UTF8
  (4 rows)

Alternatively, simply run :command:`psql -l` and check the output. If
your OMERO database is not Unicode-encoded with ``UTF8`` then it must be
re-encoded.

If you have the :command:`pg_upgradecluster` command available then its
``--locale`` option can effect the change in encoding. Otherwise,
create a Unicode-encoded dump of your database: dump it :ref:`as before
<back-up-the-db>` but to a different dump file and with an additional
``-E UTF8`` option. Then, create a Unicode-encoded database for
OMERO and restore that dump into it with :command:`pg_restore`,
similarly to :ref:`effecting a rollback <restore-the-db>`. If required
to achieve this, the ``-E UTF8`` option is accepted by both
:command:`initdb` and :command:`createdb`.

Run the upgrade script
""""""""""""""""""""""

You **must** use the same username and password you have defined during
:doc:`unix/server-installation`. For a large production system you
should plan for the fact that the upgrade script may take several hours
to run.

.. parsed-literal::

    $ cd OMERO.server
    $ psql -h localhost -U **db_user** **omero_database** < sql/psql/|current_dbver|/|previous_dbver|.sql
    Password for user **db_user**:
    ...
    ...
                               status
    ---------------------------------------------------------------------
                                                                        +
                                                                        +
                                                                        +
    YOU HAVE SUCCESSFULLY UPGRADED YOUR DATABASE TO VERSION |current_dbver| +
                                                                        +
                                                                        +

    (1 row)


If you are upgrading from a server earlier than 5.3, then
you must run the earlier upgrade scripts in sequence before the one
above. There is no need to download and run the server from an
intermediate major release but you must still study the upgrade
instructions for earlier versions in case there are additional steps.
For example, any optional SQL scripts that affect the database probably
run only on the specific version before the next upgrade script.

.. note::

   If you perform the database upgrade using *SQL shell*, make sure you are
   connected to the database using **db_user** before running the script. See
   :forum:`this forum thread <viewtopic.php?f=5&t=7778>` for more information.

.. warning::

   The :file:`sql/psql/OMERO5.4__0/OMERO5.3__1.sql` script referenced by
   the above :program:`psql` command assumes upgrade from OMERO 5.3.4.
   If you are instead currently running OMERO 5.3.3 or an earlier 5.3.x
   version then you upgrade the database directly to OMERO 5.4.0 by
   using the above command with
   :file:`sql/psql/OMERO5.4__0/OMERO5.3__0.sql`.

Optimize an upgraded database (optional)
""""""""""""""""""""""""""""""""""""""""

After you have run the upgrade script, you may want to optimize your
database which can both save disk space and speed up access times.

.. parsed-literal::

    $ psql -h localhost -U **db_user** **omero_database** -c 'VACUUM FULL VERBOSE ANALYZE;'

Merge script changes
^^^^^^^^^^^^^^^^^^^^

If any new official scripts have been added under ``lib/scripts`` or if
you have modified any of the existing ones, then you will need to backup
your modifications. Doing this, however, is not as simple as copying the
directory over since the core developers will have also improved these
scripts.

For further information on managing your scripts, refer to
:doc:`installing-scripts`. If you require help, please contact the OME
developers.

Update your environment variables and memory settings
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Environment variables
"""""""""""""""""""""

If you changed the directory name where the |version_openmicroscopy| server code
resides, make sure to update any system environment variables. Before
restarting the server, make sure your :envvar:`PATH` system environment
variable is pointing to the new location. Also make sure the :envvar:`OMERODIR`
environment variable is set to the location of the server.

See :ref:`server_env` for more information.

JVM memory settings
"""""""""""""""""""

Your memory settings should be copied along with :file:`etc/grid/config.xml`,
but you can check the current settings by running :program:`omero admin jvmcfg`.
See :ref:`jvm_memory_settings` for more information.

Dependencies
^^^^^^^^^^^^

.. warning::
    Upgrading to OMERO 5.6.12 or higher requires an upgrade to OMERO.py 5.19.4 or higher
    
While upgrading the server you should keep OMERO.py dependencies
up to date to ensure that security updates are applied:

.. parsed-literal::

      $ # first, activate virtualenv where omero-py is installed. Then upgrade:
      $ pip install --upgrade 'omero-py>=\ |version_py|'

.. _server_certificates:

Server certificate
^^^^^^^^^^^^^^^^^^

The server should be configured with at least a self-signed certificate to allow
clients to establish secure connections.

Since OMERO 5.6.2, the recommended way to ensure that all OMERO server installations have
at minimum, a self-signed certificate is to use the
`omero-certificates <https://pypi.org/project/omero-certificates/>`_ plugin.
The plugin will generate or update your self-signed certificates and configure the OMERO.server.
For the configuration to take effect, the server needs to be restarted.
If you prefer to configure the OMERO server certificate manually, check
:doc:`/sysadmins/client-server-ssl`.

If your server has been configured with a version of ``omero-certificates`` older than
0.3.0 or manually, the configuration may need to be upgraded in particular to
disallow the `deprecated TLS 1.0 and 1.1 protocols <https://datatracker.ietf.org/doc/html/rfc8996>`_.

To do so, activate the virtual environment where the server Python dependencies are installed,
upgrade ``omero-certificates`` to version 0.3.0 or later, remove the
:property:`omero.glacier2.IceSSL.Protocols` and :property:`omero.glacier2.IceSSL.ProtocolVersionMax`
configurations and finally re-execute the :program:`omero certificates` command::

    $ pip install "omero-certificates>=0.3"
    $ omero config set omero.glacier2.IceSSL.Protocols
    $ omero config set omero.glacier2.IceSSL.ProtocolVersionMax
    $ omero certificates

.. note::

   From version 0.3.0, the :program:`omero certificates` command adds TLS 1.3 to the list of
   TLS protocols allowed assuming the OMERO.server enviroment supports the protocol.
   In order to negotiate this protocol, clients will also need to be upgraded to depend
   on ``omero-blitz`` 5.7.0 or greater (Java) or ``omero-py`` 5.15.0 or greater (Python).

Restart your server
^^^^^^^^^^^^^^^^^^^

-  Following a successful database upgrade, you can start the server.

   .. parsed-literal::

       $ omero admin start

-  If anything goes wrong, please send the output of
   :program:`omero admin diagnostics` to
   the `forum <https://www.openmicroscopy.org/forums>`_.

.. _restore-the-db:

Restore a database backup
^^^^^^^^^^^^^^^^^^^^^^^^^

If the upgraded database or the new server version do not work for you,
or you otherwise need to rollback to a previous database backup, you may
want to restore a database backup. To do so, create a new database,

.. parsed-literal::

    $ createdb -h localhost -U postgres -E UTF8 -O **db_user** omero_from_backup

restore the previous archive into this new database,

::

    $ pg_restore -Fc -d omero_from_backup before_upgrade.db.dump

and configure your server to use it.

::

    $ omero config set omero.db.name omero_from_backup

