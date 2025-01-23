FROM --platform=linux/amd64 illinois241/grader:prod
RUN mkdir /opt/cs341
COPY setup.sh /opt/cs341/setup.sh
COPY utils.sh /opt/cs341/utils.sh
RUN chown root:root /opt/cs341/utils.sh
RUN chmod 755 /opt/cs341/utils.sh
RUN useradd -rm -d /home/cs341user -s /bin/bash -g root -G sudo -u 1001 cs341user
RUN apt install -y sudo sshpass iputils-ping
USER cs341user
RUN echo "source /opt/cs341/utils.sh" >> /home/cs341user/.bashrc