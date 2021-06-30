FROM jupyterhub/k8s-hub:0.9.0

USER root
RUN pip3 install --no-cache-dir -U \
    PyJWT

COPY imageedit_1_6604815272.png /usr/local/share/jupyterhub/static/images/imageedit_1_6604815272.png

USER ${NB_USER}