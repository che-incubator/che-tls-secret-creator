# Che TLS certificates and secrets creation image

This images generates TLS certificates required for Eclipse Che deployment and creates corresponding secrets in Eclipse Che dedicated namespace.
It is used as Kubernetes job image and should be run before Eclipse Che deploying process is started.
The job is usually started from Che operator reconcile loop.

All parameters to this image is passed as environment variables.

Required parameters:

 - `DOMAIN` should be set with the list of cluster public domains with or without wildcard.

Optional parameters:

 - `CHE_NAMESPACE` is the namespace name into which Eclipse Che should be deployed.
   If now specified, default value `che` is used.
 - `CHE_SERVER_TLS_SECRET_NAME` is the name of TLS secret into which generated TLS certificate should be saved.
   The namespace is defined by `CHE_NAMESPACE` environment variable.
   Default value is `che-tls`.
 - `CHE_CA_CERTIFICATE_SECRET_NAME` is the name of the secret in which Che CA certificate should be saved.
   This certificate should be shared with all users and each user should add it into OS or browser trust store.
   The namespace is defined by `CHE_NAMESPACE` environment variable.
   Default value is `self-signed-certificate`.
 - `LABELS` is a space separated list of labels to add to the generated secret.
   Could be empty.

Image repository is `quay.io/eclipse/che-tls-secret-creator` and could be found [here](https://quay.io/repository/eclipse/che-tls-secret-creator).
