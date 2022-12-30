#!/usr/bin/env bash

# Este script es para controlar el servidor de pantalla Screenly OSE usando su API REST.
# Documentación: https://ose.demo.screenlyapp.com/api/docs/
# Swagger: https://ose.demo.screenlyapp.com/api/swagger.json

set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on undeclared variable
set -o pipefail  # don't hide errors within pipes
# set -o xtrace  # track what is running - debugging

#Colors
color="false"
RED=""
BLUE=""
GREEN=""
ENDCOLOR=""

#Variables
option=${1:-}
#server="https://ose.demo.screenlyapp.com"
server="http://localhost:8000"
force="false"

# Set magic variables for current file & dir
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # <-- get path of the script
__file="${__dir}/$(basename "${BASH_SOURCE[0]}")" # <-- get full path name of the script
__base="$(basename "${__file}" .sh)" # <-- get name of the script
__root="$(cd "$(dirname "${__dir}")" && pwd)" # <-- get root path of the script

# Parametros necesarios
# -u: Usuario
# -p: Contraseña
# -s: Servidor
# -a: Acción
# -h: Ayuda

# Parametros opcionales
# -f: Forzar


# Recuperar parámetros
while getopts ":u:p:s:a:f:c" opt; do
  case $opt in
    u) user="$OPTARG"
    ;;
    p) pass="$OPTARG"
    ;;
    s) server="$OPTARG"
    ;;
    a) action="$OPTARG"
    ;;
    f) force="true"
    ;;
    c) color="true"
    ;;
    \?) echo -e "${RED}Opción inválida: -$OPTARG${ENDCOLOR}" >&2
    ;;
  esac
done

# Si no se especifica ninguna opción, mostrar el menú de ayuda
if [ -z "$option" ]; then
    help
    exit 1
fi

# Funciones

# Fnción para comprobar si el usuario ha marcado la opción -f
function check_force {
    if [ -z "$force" ]; then
        echo -e "${RED}No se ha marcado la opción -f${ENDCOLOR}"
        exit 1
        else
        echo -e "${GREEN}Se ha marcado la opción -f${ENDCOLOR}"
    fi
}

# Función para comprobar que el servidor está activo
function check_server() {
    if curl -s --head  --request GET "$server" | grep "200 OK" > /dev/null; then
        echo -e "${GREEN}Servidor activo${ENDCOLOR}"
    else
        echo -e "${RED}Servidor inactivo${ENDCOLOR}"
        exit 1
    fi
}

# Función para mostrar el menú de ayuda
function help() {
    echo -e "${BLUE}Uso: ${__base} -u usuario -p contraseña -s servidor -a accion${ENDCOLOR}"
    echo -e "${BLUE}Ejemplo: ${__base} -u admin -p admin -s"
}

# Función para listar assets
function list_assets() {
    # Listar assets y convertir output JSON a tabla con columnas y titulo de columna con api v1.2
    curl -s -X GET "${server}/api/v1.2/assets" -H "accept: application/json" -u "${user}:${pass}" | jq -r '.[] | [.asset_id, .name, .uri, .duration, .mimetype, .is_enabled] | @tsv' | column -t -s $'\t' -N "ASSSET_ID,NAME,URI,DURATION,MIMETYPE,IS_ENABLED"
}

# Función para comprobar si el asset se ha eliminado correctamente
function check_delete() {
    if [[ $result == *"error"* ]]; then
        echo -e "${RED}El asset no ha sido eliminado${ENDCOLOR}"
        echo -e "$result"
    else
    sleep 2
    # Listar assets usando list_assets(), usar grep para comprobar si el asset se ha eliminado
        if list_assets | grep -q "$id"; then
                echo -e "${RED}El asset no ha sido eliminado${ENDCOLOR}"
            else
                echo -e "${GREEN}El asset ha sido eliminado${ENDCOLOR}"
        fi
    fi
}

# Función para eliminar assets
function delete_assets() {
    list_assets
    echo -e "${BLUE}Introduce el ID del asset a eliminar:${ENDCOLOR}"
    read -r id
    # Pedir confirmación para eliminar el asset
    echo -e "${BLUE}¿Estás seguro de que quieres eliminar el asset con ID ${id}?${ENDCOLOR}"
    read -p "y/n: " -n 1 -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        result=$(curl -s -X DELETE "${server}/api/v1.2/assets/${id}" -H "accept: application/json" -u "${user}:${pass}")
        # Comprobar si el asset se ha eliminado correctamente
        check_delete
        else
        echo -e "${RED}Operación cancelada${ENDCOLOR}"
    fi
}

# Función para crear backup
function create_backup() {
    response=$(curl -X POST "${server}/api/v1.2/backup" -H "accept: application/json" -u "${user}:${pass}")
    # Comprobar si ha sido creado correctamente, comprobando si $response contiene "error"
    if [ "$response" == '{"error": "list indices must be integers, not str"}' ]; then
        echo -e "${GREEN}Backup creado correctamente${ENDCOLOR}"
    else
        echo -e "${RED}Error al crear el backup${ENDCOLOR}"
    fi
}

# Función para acceder a todos los datos de un asset con su ID
function get_asset() {
    curl -s -X GET "${server}/api/v1.2/assets/${id}" -H "accept: application/json" -u "${user}:${pass}" | jq -r '.[] | [.asset_id, .name, .uri, .duration, .mimetype, .is_enabled] | @tsv' | column -t -s $'\t' -N "ASSSET_ID,NAME,URI,DURATION,MIMETYPE,IS_ENABLED"
}

# Función para cambiar la reproducción
function control() {
    if curl -s -X GET "${server}/api/v1/assets/control/${action}" -H "accept: application/json" -u "${user}:${pass}" | grep "Asset switched" > /dev/null; then
        echo -e "${GREEN}Acción ejecutada correctamente${ENDCOLOR}"
    else
        echo -e "${RED}Error al ejecutar la acción${ENDCOLOR}"
    fi
}

# Función para eliminar todos los assets de la lista
function delete_all_assets() {
    list_assets
    echo -e "${BLUE}¿Estás seguro de que quieres eliminar todos los assets?${ENDCOLOR}"
    read -p "y/n: " -n 1 -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Recorrer la lista de assets y eliminarlos uno a uno
        for id in $(list_assets | awk '{print $1}'| tail +2); do
            result=$(curl -s -X DELETE "${server}/api/v1.2/assets/${id}" -H "accept: application/json" -u "${user}:${pass}")
            # Comprobar si el asset se ha eliminado correctamente
            check_delete
        done
    else
        echo -e "${RED}Operación cancelada${ENDCOLOR}"
    fi
}

# Función para renombrar assets
function rename_asset() {
    list_assets
    echo -e "${BLUE}Introduce el ID del asset a renombrar:${ENDCOLOR}"
    read -r id
    echo -e "${BLUE}Introduce el nuevo nombre:${ENDCOLOR}"
    read -r name
    # Obtener todos los datos del asset en json
    json=$(curl -s -X GET "${server}/api/v1.2/assets/${id}" -H "accept: application/json" -u "${user}:${pass}")
    # Modificar el nombre del asset
    json=$(echo "$json" | jq --arg jqname "$name" '.name = $jqname')
    # Enviar los datos modificados al servidor
    response=$(curl -s -X PUT "${server}/api/v1.2/assets/${id}" -H "accept: application/json" -H "Content-Type: application/json" -u "${user}:${pass}" -d "$json" | jq)
    # Comprobar si el asset renombrado existe, listando los assets y filtrando por el ID y el nombre introducido
    if list_assets | grep "$id" | grep -q "$name"; then
        echo -e "${GREEN}El asset ha sido renombrado${ENDCOLOR}"
    else
        echo -e "${RED}Error al renombrar el asset${ENDCOLOR}"
    fi
}

# Función para cambiar el estado de un asset
function change_state() {
    list_assets
    echo -e "${BLUE}Introduce el ID del asset a cambiar:${ENDCOLOR}"
    read -r id
    echo -e "${BLUE}Introduce el nuevo estado (0/1):${ENDCOLOR}"
    read -r state
    # Obtener todos los datos del asset en json
    json=$(curl -s -X GET "${server}/api/v1.2/assets/${id}" -H "accept: application/json" -u "${user}:${pass}")
    # Modificar el estado del asset
    json=$(echo "$json" | jq --arg state "$state" '.is_enabled = $state')
    # Enviar los datos modificados al servidor
    curl -s -X PUT "${server}/api/v1.2/assets/${id}" -H "accept: application/json" -H "Content-Type: application/json" -u "${user}:${pass}" -d "$json"
    # Tiempo para que el servidor actualice los datos
    sleep 2
    # Comprobar si el asset se ha cambiado correctamente
    if get_asset | grep -q "$state"; then
        echo -e "${GREEN}El asset ha sido cambiado${ENDCOLOR}"
    else
        echo -e "${RED}Error al cambiar el asset${ENDCOLOR}"
    fi
}

# Si color=true, mostrar los colores
if [ "$color" = true ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    ENDCOLOR='\033[0m'
fi

# Ejecutar función list_assets si se especifica la opción -a list
if [ "$action" = "list" ]; then
    list_assets
fi

# Ejecutar función delete_assets si se especifica la opción -a delete
if [ "$action" = "delete" ]; then
    delete_assets
fi

# Ejecutar función control si se especifica la opción -a "next" o "prev"
if [ "$action" = "next" ] || [ "$action" = "prev" ]; then
    control
fi

# Ejecutar función rename_asset si se especifica la opción -a rename
if [ "$action" = "rename" ]; then
    rename_asset
fi