# Stateless Arch Generator<h1>

**Veja [Stateless Arch](https://gitlab.com/vmath3us/stateless-arch.git)**

Este script precisa somente do Podman (preferencialmente rootless)

No host, ele irá gerar um container do ArchLinux, com um volume para cache, e montando a pasta corrente. Modo de internet host  (explicado mais à frente).
Dentro do container, ele ira instalar dependẽncias necessárias para rodar o qemu, e o aria2, além de clonar **Stateless Arch**.

Serão geradas duas imagens de disco vazias, uma para servir de apoio para a cache do pacman, e outra para a instalação propriamente dita. Flags GPT serão configuradas, e serão usadas para comunicação entre o container e a vm.

[Após baixar a iso do arch, e separadamente, kernel e initrd](https://geo.mirror.pkgbuild.com/iso/latest/), será gerado um initrd customizado, embutindo nele arquivos (por exemplo a lista de pacotes), usando-o como "área de transferência" entre o container e a máquina virtual. O qemu será executado, usando 2 núcleos e 4GB de RAM. O console da VM será transmitido no terminal do host. Ao concluir o boot, a VM automaticamente irá fazer todas as operações descritas no intervado **on-vm** do script, e ao fim (após interação com o usuário), desligar. No ambiente do container, será verificado (via flag GPT), se a instalação foi bem sucedida. Se sim, e após confirmação do usuário, o qemu será executado novamente, mas tendo como alvo agora a imagem final, e oferecendo visão gráfica via SPICE, em localhost:5900 (por isso net --host). A VM pode ser desligada normalmente via interface, ou interrompida (com todos os riscos que isso acarreta), via ctrl-c no terminal.

Terminada essa execução (ou caso ela seja cancelada), mais instruções serão passadas no terminal, dentro de um less. Sair do less encerra a execução do container. Excluir o container e o volume de cache associado são de sua responsabilidade. O container e a imagem de cache podem ser reusados N vezes, e pode-se editar packagelist.pacman para gerar uma instalação com outros pacotes. Pode-se alterar o tamanho das imagens de cache e de instalação. Mais detalhes são visíveis lendo o script em si.
