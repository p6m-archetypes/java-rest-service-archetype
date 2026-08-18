package {{ group_id }}.persistence;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;

import java.util.UUID;

/**
 * The standard entity every p6m service persists (p6m standards S2): {@code { id, display_name }}.
 * The table is service-internal; the name-derived API surface lives at the transport boundary.
 */
@Entity
@Table(name = "{{ entity_name }}s")
public class {{ EntityName }}Entity {

    @Id
    @Column(name = "id", length = 36)
    private String id;

    @Column(name = "display_name", nullable = false)
    private String displayName;

    protected {{ EntityName }}Entity() {
    }

    public {{ EntityName }}Entity(String displayName) {
        this.displayName = displayName;
    }

    @PrePersist
    void generateId() {
        if (id == null) {
            id = UUID.randomUUID().toString();
        }
    }

    public String getId() {
        return id;
    }

    public String getDisplayName() {
        return displayName;
    }

    public void setDisplayName(String displayName) {
        this.displayName = displayName;
    }
}
