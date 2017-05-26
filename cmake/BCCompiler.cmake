#
# compiler detection
#

if (NOT DEFINED CMAKE_BC_COMPILER)
    set(CLANG_CXX_EXECUTABLE_NAME "clang++")
    set(LLVMLINK_EXECUTABLE_NAME "llvm-link")

    if (DEFINED WIN32)
        set(CLANG_CXX_EXECUTABLE_NAME "${CLANG_CXX_EXECUTABLE_NAME}.exe")
        set(LLVMLINK_EXECUTABLE_NAME "${LLVMLINK_EXECUTABLE_NAME}.exe")
    endif ()

    if (DEFINED ENV{LLVM_INSTALL_PREFIX})
        message(STATUS "Setting LLVM_INSTALL_PREFIX from the environment variable...")
        set(LLVM_INSTALL_PREFIX $ENV{LLVM_INSTALL_PREFIX})
    endif ()

    if ("${CMAKE_CXX_COMPILER}" STREQUAL "${CLANG_CXX_EXECUTABLE_NAME}")
        set(CLANG_PATH "${CMAKE_CXX_COMPILER}")

    else ()
        find_program(CLANG_PATH
            NAMES "${CLANG_CXX_EXECUTABLE_NAME}"
            PATHS "/usr/bin" "/usr/local/bin" "${LLVM_INSTALL_PREFIX}/bin" "${LLVM_TOOLS_BINARY_DIR}" "C:/Program Files/LLVM/bin" "C:/Program Files (x86)/LLVM/bin"
        )
    endif ()

    find_program(LLVMLINK_PATH
        NAMES "${LLVMLINK_EXECUTABLE_NAME}"
        PATHS "/usr/bin" "/usr/local/bin" "${LLVM_INSTALL_PREFIX}/bin" "${LLVM_TOOLS_BINARY_DIR}" "C:/Program Files/LLVM/bin" "C:/Program Files (x86)/LLVM/bin"
    )

    if ((NOT "${CLANG_PATH}" MATCHES "CLANG_PATH-NOTFOUND") AND (NOT "${LLVMLINK_PATH}" MATCHES "LLVMLINK_PATH-NOTFOUND"))
        file(WRITE "${CMAKE_BINARY_DIR}/emitllvm.test.cpp" "int main(int argc, char* argv[]){return 0;}\n\n")

        execute_process(COMMAND "${CLANG_PATH}" "-emit-llvm" "-c" "emitllvm.test.cpp" "-o" "emitllvm.test.cpp.bc"
            WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
            RESULT_VARIABLE AOUT_IS_NOT_BC
            OUTPUT_QUIET ERROR_QUIET
        )

        if (NOT "${AOUT_IS_NOT_BC}" STREQUAL "0")
            message(SEND_ERROR "The following compiler is not suitable to generate bitcode: ${CLANG_PATH}")
        else ()
            message(STATUS "The following compiler has been selected to compile the bitcode: ${CLANG_PATH}")

            set(CMAKE_BC_COMPILER "${CLANG_PATH}" CACHE PATH "Bitcode Compiler")
            set(CMAKE_BC_LINKER "${LLVMLINK_PATH}" CACHE PATH "Bitcode Linker")
        endif ()
    endif ()
endif ()

#
# utils
#

# this is the runtime target generator, used in a similar way to add_executable
set(add_runtime_usage "add_runtime(target_name SOURCES <src1 src2> ADDRESS_SIZE <size> DEFINITIONS <def1 def2> BCFLAGS <bcflag1 bcflag2> LINKERFLAGS <lnkflag1 lnkflag2> INCLUDEDIRECTORIES <path1 path2>")

function (add_runtime target_name)
    if (NOT DEFINED CMAKE_BC_COMPILER)
        message(FATAL_ERROR "The bitcode compiler was not found!")
    endif ()

    if (NOT DEFINED CMAKE_BC_LINKER)
        message(FATAL_ERROR "The bitcode linker was not found!")
    endif ()

    foreach (macro_parameter ${ARGN})
        if ("${macro_parameter}" STREQUAL "SOURCES")
            set(state "${macro_parameter}")
            continue ()

        elseif ("${macro_parameter}" STREQUAL "ADDRESS_SIZE")
            set(state "${macro_parameter}")
            continue ()

        elseif ("${macro_parameter}" STREQUAL "DEFINITIONS")
            set(state "${macro_parameter}")
            continue ()

        elseif ("${macro_parameter}" STREQUAL "BCFLAGS")
            set(state "${macro_parameter}")
            continue ()

        elseif ("${macro_parameter}" STREQUAL "LINKERFLAGS")
            set(state "${macro_parameter}")
            continue ()

        elseif ("${macro_parameter}" STREQUAL "INCLUDEDIRECTORIES")
            set(state "${macro_parameter}")
            continue ()
        endif ()

        if ("${state}" STREQUAL "SOURCES")
            list(APPEND source_file_list "${macro_parameter}")

        elseif ("${state}" STREQUAL "ADDRESS_SIZE")
            if (DEFINED address_size_bits_found)
                message(SEND_ERROR "The ADDRESS_SIZE parameter has been specified twice!")
            endif ()

            if (NOT "${macro_parameter}" MATCHES "^[0-9]+$")
                message(SEND_ERROR "Invalid ADDRESS_SIZE parameter passed to add_runtime")
            endif ()

            list(APPEND definitions "ADDRESS_SIZE_BITS=${macro_parameter}")
            set(address_size_bits_found True)

        elseif ("${state}" STREQUAL "DEFINITIONS")
            list(APPEND definition_list "-D${macro_parameter}")

        elseif ("${state}" STREQUAL "BCFLAGS")
            list(APPEND bc_flag_list "${macro_parameter}")

        elseif ("${state}" STREQUAL "LINKERFLAGS")
            list(APPEND linker_flag_list "${macro_parameter}")

        elseif ("${state}" STREQUAL "INCLUDEDIRECTORIES")
            list(APPEND include_directory_list "-I${macro_parameter}")

        else ()
            message(SEND_ERROR "Syntax error. Usage: ${add_runtime_usage}")
        endif ()
    endforeach ()

    if (NOT address_size_bits_found)
        message(SEND_ERROR "Missing address size.")
    endif ()

    if ("${source_file_list}" STREQUAL "")
        message(SEND_ERROR "No source files specified.")
    endif ()

    foreach (source_file ${source_file_list})
        get_filename_component(source_file_name "${source_file}" NAME)
        get_filename_component(absolute_source_file_path "${source_file}" ABSOLUTE)
        set(absolute_output_file_path "${CMAKE_CURRENT_BINARY_DIR}/${target_name}_${source_file_name}.bc_o")

        add_custom_command(OUTPUT "${absolute_output_file_path}"
            COMMAND "${CMAKE_BC_COMPILER}" ${bc_flag_list} ${definition_list} ${include_directory_list} -c "${absolute_source_file_path}" -o "${absolute_output_file_path}"
            DEPENDS "${absolute_source_file_path}"
            IMPLICIT_DEPENDS CXX "${absolute_source_file_path}"
            COMMENT "Building LLVM bitcode ${absolute_output_file_path}"
            VERBATIM
        )

        set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_MAKE_CLEAN_FILES "${absolute_output_file_path}")
        list(APPEND bitcode_file_list "${absolute_output_file_path}")
    endforeach ()

    set(absolute_target_path "${CMAKE_CURRENT_BINARY_DIR}/${target_name}.bc")

    add_custom_command(OUTPUT "${absolute_target_path}"
        COMMAND "${CMAKE_BC_LINKER}" ${linker_flag_list} -o "${absolute_target_path}" ${bitcode_file_list}
        DEPENDS ${bitcode_file_list}
        COMMENT "Linking LLVM bitcode ${absolute_target_path}"
    )

    set(DIRECTORY APPEND PROPERTY ADDITIONAL_MAKE_CLEAN_FILES "${absolute_target_path}")

    add_custom_target("${target_name}" ALL DEPENDS "${absolute_target_path}")
    set_property(TARGET "${target_name}" PROPERTY LOCATION "${absolute_target_path}")

    set("${target_name}_location" "${absolute_target_path}" PARENT_SCOPE)
endfunction ()