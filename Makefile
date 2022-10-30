BIN_DIR	= ${HOME}/bin
MAN_DIR	= ${HOME}/man/man1

OWNER	= ${USER}
GROUP	= ${USER}

BIN_MODE	= 755
CONFIG_MODE	= 744
MAN_MODE	= 744

spam-summary:
	@echo do a 'make install' to install spam-summary

directories:
	@if [ ! -d ${BIN_DIR} ]; then \
		mkdir -p ${BIN_DIR} ; \
	fi 
	@if [ ! -d ${MAN_DIR} ]; then \
		mkdir -p ${MAN_DIR} ; \
	fi

bin: spam-summary.plx
	install -p -m ${BIN_MODE} -o ${OWNER} -g ${GROUP} \
		spam-summary.plx ${BIN_DIR}/spam-summary

manpage: spam-summary.1
	install -p -m ${MAN_MODE} -o ${OWNER} -g ${GROUP} \
		spam-summary.1 ${MAN_DIR}/spam-summary.1

install: directories bin manpage
