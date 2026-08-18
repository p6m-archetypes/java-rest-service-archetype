package {{ group_id }}.persistence;

import org.springframework.data.jpa.repository.JpaRepository;

public interface {{ EntityName }}Repository extends JpaRepository<{{ EntityName }}Entity, String> {
}
